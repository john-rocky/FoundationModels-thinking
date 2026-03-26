import Foundation

// MARK: - Critique Loop Pipeline
// Answer -> Review -> Final Answer (multi-turn session)

public struct CritiqueLoopPipeline: Pipeline, Sendable {
    public let name = "CritiqueLoop"
    public let description = "Answer → Review → Final (multi-turn session)"
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
        await context.emit(.pipelineStarted(pipelineName: name, stageCount: 3 + searchStageCount))

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
                    webSearchContext = "\n\n[Web Search Results]\n\(truncate(ws.content, to: 600))"
                }
            }

            // Build memory context
            let memory = await context.getRetrievedMemory()
            var memoryContext = ""
            if !memory.isEmpty {
                memoryContext = formatMemoryContext(memory)
            }

            // Require multi-turn session support
            guard let sessionProvider = context.modelProvider as? ModelSessionProvider else {
                let direct = DirectPipeline(configuration: configuration)
                return try await direct.execute(query: query, context: context)
            }

            let instructions = localizedFinalAnswerSystemPrompt(
                "You are an assistant that answers carefully and reviews your own work.",
                language: context.language
            )

            let session = sessionProvider.createSession(instructions: instructions)

            // --- Turn 1: Solve ---
            await context.emit(.stageStarted(stageName: "Solve", stageKind: .solve, index: stageIndex))
            await context.traceCollector.record(event: .stageStarted(stage: "Solve", kind: .solve, input: query))

            let solvePrompt = "Answer the following question.\n\nQuestion: \(query)\(memoryContext)\(webSearchContext)"

            let solveRaw = try await streamingSessionGenerate(
                stageName: "Solve",
                prompt: solvePrompt,
                session: session,
                context: context
            )

            let solveOutput = parseOutput(raw: solveRaw, kind: .solve)
            allOutputs.append(solveOutput)
            await context.setOutput(solveOutput, for: "Solve")
            await context.traceCollector.record(event: .stageCompleted(stage: "Solve", output: solveOutput))
            await context.emit(.stageCompleted(stageName: "Solve", stageKind: .solve, output: solveOutput, index: stageIndex))
            stageIndex += 1

            // --- Turn 2: Critique (session sees full Solve output) ---
            await context.emit(.stageStarted(stageName: "Critique", stageKind: .critique, index: stageIndex))
            await context.traceCollector.record(event: .stageStarted(stage: "Critique", kind: .critique, input: ""))

            let critiquePrompt = """
                Review your answer above.
                - Are there any factual errors?
                - Any logical gaps or oversights?
                - Could the explanation be improved?
                Point out specific issues if any. If the answer is correct, say "No issues found."
                """

            let critiqueRaw = try await streamingSessionGenerate(
                stageName: "Critique",
                prompt: critiquePrompt,
                session: session,
                context: context
            )

            let critiqueOutput = parseOutput(raw: critiqueRaw, kind: .critique)
            allOutputs.append(critiqueOutput)
            await context.setOutput(critiqueOutput, for: "Critique")
            await context.traceCollector.record(event: .stageCompleted(stage: "Critique", output: critiqueOutput))
            await context.emit(.stageCompleted(stageName: "Critique", stageKind: .critique, output: critiqueOutput, index: stageIndex))
            stageIndex += 1

            // --- Turn 3: Final Answer (session sees both Solve and Critique) ---
            await context.emit(.stageStarted(stageName: "Finalize", stageKind: .finalize, index: stageIndex))
            await context.traceCollector.record(event: .stageStarted(stage: "Finalize", kind: .finalize, input: ""))

            let finalPrompt = "Based on your review above, write your final answer. Fix any issues you identified, and keep the parts that were correct."

            let finalRaw = try await streamingSessionGenerate(
                stageName: "Finalize",
                prompt: finalPrompt,
                session: session,
                context: context
            )

            let finalOutput = parseOutput(raw: finalRaw, kind: .finalize)
            allOutputs.append(finalOutput)
            await context.setOutput(finalOutput, for: "Finalize")
            await context.traceCollector.record(event: .stageCompleted(stage: "Finalize", output: finalOutput))
            await context.emit(.stageCompleted(stageName: "Finalize", stageKind: .finalize, output: finalOutput, index: stageIndex))

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
