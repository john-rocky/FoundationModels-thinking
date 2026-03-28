import Foundation

// MARK: - Sequential Pipeline
// Think (separate session) -> Answer (separate session)

public struct SequentialPipeline: Pipeline, Sendable {
    public let name = "Sequential"
    public let description = "Think → Answer (separate sessions)"
    public let configuration: PipelineConfiguration

    public var stages: [any Stage] { [] }

    public init(configuration: PipelineConfiguration = .default) {
        self.configuration = configuration
    }

    public func execute(query: String, context: PipelineContext) async throws -> PipelineResult {
        let startTime = Date.now
        await context.traceCollector.setPipeline(name: name, executionId: context.executionId)
        await context.traceCollector.record(event: .pipelineStarted(name: name, query: query))

        let searchStageCount = configuration.webSearchEnabled ? 1 : 0
        await context.emit(.pipelineStarted(pipelineName: name, stageCount: 2 + searchStageCount))

        var allOutputs: [StageOutput] = []
        var stageIndex = 0

        do {
            // Optional: Web Search
            var webSearchContext = ""
            if configuration.webSearchEnabled {
                let wsOutput = try await executeWebSearchIfEnabled(
                    query: query, context: context, configuration: configuration,
                    allOutputs: &allOutputs, stageIndex: &stageIndex
                )
                if let ws = wsOutput, ws.metadata["searchDecision"] == "searched" {
                    webSearchContext = "\n\n\(truncate(ws.content, to: configuration.webSearchContextBudget))"
                }
            }

            // Build memory context
            let memory = await context.getRetrievedMemory()
            var memoryContext = ""
            if !memory.isEmpty {
                memoryContext = formatMemoryContext(memory)
            }

            // --- Stage 1: Think (fresh session) ---
            await context.emit(.stageStarted(stageName: "Think", stageKind: .think, index: stageIndex))
            await context.traceCollector.record(event: .stageStarted(stage: "Think", kind: .think, input: query))

            let thinkSystem = localizedSystemPrompt(
                "You analyze problems carefully before solving. Be brief and precise.",
                language: context.language
            )
            let thinkPrompt = """
                Read the problem carefully. Before solving, identify:
                1. What is being asked
                2. Key numbers, facts, or conditions
                3. Common mistakes to avoid
                Write a brief analysis only. Do not write the final answer yet.

                Problem: \(query)\(memoryContext)\(webSearchContext)
                """

            let thinkRaw: String
            do {
                thinkRaw = try await streamingGenerate(
                    stageName: "Think",
                    systemPrompt: thinkSystem,
                    userPrompt: thinkPrompt,
                    context: context
                )
            } catch let error as ModelError where error.isContextTooLong && !memory.isEmpty {
                thinkRaw = try await streamingGenerate(
                    stageName: "Think",
                    systemPrompt: thinkSystem,
                    userPrompt: "Read the problem carefully. Identify what is asked, key facts, and common mistakes. Do not solve yet.\n\nProblem: \(query)\(webSearchContext)",
                    context: context
                )
            }

            let thinkOutput = parseOutput(raw: thinkRaw, kind: .think)
            allOutputs.append(thinkOutput)
            await context.setOutput(thinkOutput, for: "Think")
            await context.traceCollector.record(event: .stageCompleted(stage: "Think", output: thinkOutput))
            await context.emit(.stageCompleted(stageName: "Think", stageKind: .think, output: thinkOutput, index: stageIndex))
            stageIndex += 1

            // --- Stage 2: Answer (fresh session, receives analysis) ---
            await context.emit(.stageStarted(stageName: "Finalize", stageKind: .finalize, index: stageIndex))
            await context.traceCollector.record(event: .stageStarted(stage: "Finalize", kind: .finalize, input: ""))

            let answerSystem = localizedSystemPrompt(
                "You solve problems step by step. Always end with 'Answer: [value]'.",
                language: context.language
            )
            let analysis = truncate(thinkRaw, to: 600)
            let answerPrompt = "Problem: \(query)\n\nAnalysis: \(analysis)\n\nSolve step by step using the analysis above. End with 'Answer: [your answer]'"

            let answerRaw = try await streamingGenerate(
                stageName: "Finalize",
                systemPrompt: answerSystem,
                userPrompt: answerPrompt,
                context: context
            )

            let answerOutput = parseOutput(raw: answerRaw, kind: .finalize)
            allOutputs.append(answerOutput)
            await context.setOutput(answerOutput, for: "Finalize")
            await context.traceCollector.record(event: .stageCompleted(stage: "Finalize", output: answerOutput))
            await context.emit(.stageCompleted(stageName: "Finalize", stageKind: .finalize, output: answerOutput, index: stageIndex))

        } catch {
            await context.emit(.pipelineFailed(error: "\(error)"))
            await context.finishEventStream()
            throw error
        }

        let endTime = Date.now
        let trace = await context.traceCollector.allRecords()
        await context.traceCollector.record(
            event: .pipelineCompleted(name: name, duration: endTime.timeIntervalSince(startTime))
        )

        let result = PipelineResult(
            pipelineName: name,
            query: query,
            finalOutput: allOutputs.last ?? StageOutput(stageKind: .finalize, content: ""),
            stageOutputs: allOutputs,
            trace: trace,
            startTime: startTime,
            endTime: endTime
        )

        await context.emit(.pipelineCompleted(result: result))
        await context.finishEventStream()
        return result
    }
}
