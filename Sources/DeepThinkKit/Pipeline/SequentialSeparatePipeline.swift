import Foundation

// MARK: - Sequential Pipeline (Separate Sessions)
// Think (step-by-step) -> Answer — each step uses a fresh session

public struct SequentialSeparatePipeline: Pipeline, Sendable {
    public let name = "SequentialSeparate"
    public let description = "Think step-by-step → Answer (separate sessions per step)"
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

            // --- Step 1: Think (fresh session) ---
            await context.emit(.stageStarted(stageName: "Think", stageKind: .think, index: stageIndex))
            await context.traceCollector.record(event: .stageStarted(stage: "Think", kind: .think, input: query))

            let thinkSystemPrompt = localizedSystemPrompt(
                "You are an assistant that thinks carefully before answering.",
                language: context.language
            )

            let thinkPrompt = """
                Think through this question step by step:
                1. Clarify what is being asked
                2. Identify key facts and constraints
                3. Consider your approach
                4. Check for things easy to overlook
                Write your thinking process. Do not write the final answer yet.

                Question: \(query)\(memoryContext)\(webSearchContext)
                """

            let thinkRaw = try await streamingGenerate(
                stageName: "Think",
                systemPrompt: thinkSystemPrompt,
                userPrompt: thinkPrompt,
                context: context
            )

            let thinkOutput = parseOutput(raw: thinkRaw, kind: .think)
            allOutputs.append(thinkOutput)
            await context.setOutput(thinkOutput, for: "Think")
            await context.traceCollector.record(event: .stageCompleted(stage: "Think", output: thinkOutput))
            await context.emit(.stageCompleted(stageName: "Think", stageKind: .think, output: thinkOutput, index: stageIndex))
            stageIndex += 1

            // --- Step 2: Answer (fresh session, previous thinking passed in prompt) ---
            await context.emit(.stageStarted(stageName: "Finalize", stageKind: .finalize, index: stageIndex))
            await context.traceCollector.record(event: .stageStarted(stage: "Finalize", kind: .finalize, input: ""))

            let answerSystemPrompt = localizedSystemPrompt(
                "You are an assistant that writes clear, accurate answers based on provided analysis.",
                language: context.language
            )

            let previousThinking = summarizeForNextStage(thinkOutput)
            let answerPrompt = """
                Based on the following thinking process, write your final answer.

                [Question]
                \(query)

                [Thinking Process]
                \(previousThinking)
                """

            let answerRaw = try await streamingGenerate(
                stageName: "Finalize",
                systemPrompt: answerSystemPrompt,
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
