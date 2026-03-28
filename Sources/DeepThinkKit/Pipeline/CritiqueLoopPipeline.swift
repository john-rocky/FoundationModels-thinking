import Foundation

// MARK: - Critique Loop Pipeline (2-stage)
// Solve (session A) → Critique+Fix (session B)

public struct CritiqueLoopPipeline: Pipeline, Sendable {
    public let name = "CritiqueLoop"
    public let description = "Solve → Critique+Fix (2 separate sessions)"
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

            let memory = await context.getRetrievedMemory()
            var memoryContext = ""
            if !memory.isEmpty {
                memoryContext = formatMemoryContext(memory)
            }
            let history = await context.getConversationHistory()
            var conversationContext = ""
            if !history.isEmpty {
                conversationContext = formatConversationHistory(history)
            }

            // --- Stage 1: Solve (fresh session) ---
            await context.emit(.stageStarted(stageName: "Solve", stageKind: .solve, index: stageIndex))
            await context.traceCollector.record(event: .stageStarted(stage: "Solve", kind: .solve, input: query))

            let solveSystem = localizedSystemPrompt(
                "You solve problems step by step. Show your work. Always end with 'Answer: [value]'.",
                language: context.language
            )
            let solvePrompt = "Solve this problem step by step. Show your work. End with 'Answer: [your answer]'\n\nProblem: \(query)\(conversationContext)\(memoryContext)\(webSearchContext)"

            let solveRaw: String
            do {
                solveRaw = try await streamingGenerate(
                    stageName: "Solve",
                    systemPrompt: solveSystem,
                    userPrompt: solvePrompt,
                    context: context
                )
            } catch let error as ModelError where error.isContextTooLong && !memory.isEmpty {
                solveRaw = try await streamingGenerate(
                    stageName: "Solve",
                    systemPrompt: solveSystem,
                    userPrompt: "Solve step by step. End with 'Answer: [your answer]'\n\nProblem: \(query)\(webSearchContext)",
                    context: context
                )
            }

            let solveOutput = parseOutput(raw: solveRaw, kind: .solve)
            allOutputs.append(solveOutput)
            await context.setOutput(solveOutput, for: "Solve")
            await context.traceCollector.record(event: .stageCompleted(stage: "Solve", output: solveOutput))
            await context.emit(.stageCompleted(stageName: "Solve", stageKind: .solve, output: solveOutput, index: stageIndex))
            stageIndex += 1

            // --- Stage 2: Critique + Fix in one step (fresh session) ---
            await context.emit(.stageStarted(stageName: "Finalize", stageKind: .finalize, index: stageIndex))
            await context.traceCollector.record(event: .stageStarted(stage: "Finalize", kind: .finalize, input: ""))

            let critiqueSystem = localizedSystemPrompt(
                "You review solutions and correct any errors. Always end with 'Answer: [value]'.",
                language: context.language
            )
            let solveAnswer = truncate(solveRaw, to: 600)
            let critiquePrompt = """
                Problem: \(query)

                Proposed solution:
                \(solveAnswer)

                Review this solution:
                1. Re-read the problem carefully. Was it interpreted correctly?
                2. Check each calculation step.
                3. If you find errors, fix them and give the correct answer.
                4. If the solution is correct, confirm it.
                End with 'Answer: [your answer]'
                """

            let critiqueRaw = try await streamingGenerate(
                stageName: "Finalize",
                systemPrompt: critiqueSystem,
                userPrompt: critiquePrompt,
                context: context
            )

            let critiqueOutput = parseOutput(raw: critiqueRaw, kind: .finalize)
            allOutputs.append(critiqueOutput)
            await context.setOutput(critiqueOutput, for: "Finalize")
            await context.traceCollector.record(event: .stageCompleted(stage: "Finalize", output: critiqueOutput))
            await context.emit(.stageCompleted(stageName: "Finalize", stageKind: .finalize, output: critiqueOutput, index: stageIndex))

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
