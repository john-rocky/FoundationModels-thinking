import Foundation

// MARK: - Critique Loop Pipeline (Separate Sessions)
// Answer -> Review -> Final Answer — each step uses a fresh session

public struct CritiqueLoopSeparatePipeline: Pipeline, Sendable {
    public let name = "CritiqueLoopSeparate"
    public let description = "Answer → Review → Final (separate sessions per step)"
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
                    webSearchContext = "\n\n\(truncate(ws.content, to: configuration.webSearchContextBudget))"
                }
            }

            // Build memory context
            let memory = await context.getRetrievedMemory()
            var memoryContext = ""
            if !memory.isEmpty {
                memoryContext = formatMemoryContext(memory)
            }

            // --- Step 1: Solve (fresh session) ---
            await context.emit(.stageStarted(stageName: "Solve", stageKind: .solve, index: stageIndex))
            await context.traceCollector.record(event: .stageStarted(stage: "Solve", kind: .solve, input: query))

            let solveSystemPrompt = localizedSystemPrompt(
                "You are an assistant that answers carefully and reviews your own work.",
                language: context.language
            )

            let solvePrompt = "Answer the following question.\n\nQuestion: \(query)\(memoryContext)\(webSearchContext)"

            let solveRaw = try await streamingGenerate(
                stageName: "Solve",
                systemPrompt: solveSystemPrompt,
                userPrompt: solvePrompt,
                context: context
            )

            let solveOutput = parseOutput(raw: solveRaw, kind: .solve)
            allOutputs.append(solveOutput)
            await context.setOutput(solveOutput, for: "Solve")
            await context.traceCollector.record(event: .stageCompleted(stage: "Solve", output: solveOutput))
            await context.emit(.stageCompleted(stageName: "Solve", stageKind: .solve, output: solveOutput, index: stageIndex))
            stageIndex += 1

            // --- Step 2: Critique (fresh session, previous answer passed in prompt) ---
            await context.emit(.stageStarted(stageName: "Critique", stageKind: .critique, index: stageIndex))
            await context.traceCollector.record(event: .stageStarted(stage: "Critique", kind: .critique, input: ""))

            let critiqueSystemPrompt = localizedSystemPrompt(
                "You are an expert reviewer who carefully evaluates answers for correctness and completeness.",
                language: context.language
            )

            let previousAnswer = summarizeForNextStage(solveOutput)
            let critiquePrompt = """
                Review the following answer to the given question.
                - Are there any factual errors?
                - Any logical gaps or oversights?
                - Could the explanation be improved?
                Point out specific issues if any. If the answer is correct, say "No issues found."

                [Question]
                \(query)

                [Answer to Review]
                \(previousAnswer)
                """

            let critiqueRaw = try await streamingGenerate(
                stageName: "Critique",
                systemPrompt: critiqueSystemPrompt,
                userPrompt: critiquePrompt,
                context: context
            )

            let critiqueOutput = parseOutput(raw: critiqueRaw, kind: .critique)
            allOutputs.append(critiqueOutput)
            await context.setOutput(critiqueOutput, for: "Critique")
            await context.traceCollector.record(event: .stageCompleted(stage: "Critique", output: critiqueOutput))
            await context.emit(.stageCompleted(stageName: "Critique", stageKind: .critique, output: critiqueOutput, index: stageIndex))
            stageIndex += 1

            // --- Step 3: Final Answer (fresh session, both previous outputs passed in prompt) ---
            await context.emit(.stageStarted(stageName: "Finalize", stageKind: .finalize, index: stageIndex))
            await context.traceCollector.record(event: .stageStarted(stage: "Finalize", kind: .finalize, input: ""))

            let finalSystemPrompt = localizedSystemPrompt(
                "You are an assistant that writes clear, accurate final answers incorporating review feedback.",
                language: context.language
            )

            let previousCritique = summarizeForNextStage(critiqueOutput)
            let finalPrompt = """
                Based on the original answer and the review feedback, write your final answer.
                Fix any issues identified in the review, and keep the parts that were correct.

                [Question]
                \(query)

                [Original Answer]
                \(previousAnswer)

                [Review Feedback]
                \(previousCritique)
                """

            let finalRaw = try await streamingGenerate(
                stageName: "Finalize",
                systemPrompt: finalSystemPrompt,
                userPrompt: finalPrompt,
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
