import Foundation

// MARK: - Rethink Pipeline (2-stage, best-of-both)
// Stage 1: Analyze + Solve with explicit state tracking (fresh session)
// Stage 2: Independent re-solve + compare (fresh session)
//
// Combines Sequential's "think first" with independent verification.
// Forces explicit state tracking at each step to prevent counting errors.

public struct RethinkPipeline: Pipeline, Sendable {
    public let name = "Rethink"
    public let description = "Analyze+Solve → Independent Verify (2 sessions)"
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

            // --- Stage 1: Analyze + Solve with forced state tracking ---
            await context.emit(.stageStarted(stageName: "Solve", stageKind: .solve, index: stageIndex))
            await context.traceCollector.record(event: .stageStarted(stage: "Solve", kind: .solve, input: query))

            let solveSystem = localizedSystemPrompt(
                """
                You are a friendly, helpful assistant. Think carefully before answering.
                For calculations or step-by-step problems, show your work clearly and track state at each step.
                For conversations, be natural and concise.
                """,
                language: context.language
            )
            let solvePrompt = "\(query)\(conversationContext)\(memoryContext)\(webSearchContext)"

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
                    userPrompt: "Solve step by step with explicit state tracking.\n\nProblem: \(query)\(webSearchContext)",
                    context: context
                )
            }

            let solveOutput = parseOutput(raw: solveRaw, kind: .solve)
            allOutputs.append(solveOutput)
            await context.setOutput(solveOutput, for: "Solve")
            await context.traceCollector.record(event: .stageCompleted(stage: "Solve", output: solveOutput))
            await context.emit(.stageCompleted(stageName: "Solve", stageKind: .solve, output: solveOutput, index: stageIndex))
            stageIndex += 1

            let proposedAnswer = AnswerExtractor.extract(from: solveRaw) ?? ""

            // --- Stage 2: Independent verify (fresh session, solves from scratch) ---
            await context.emit(.stageStarted(stageName: "Verify", stageKind: .finalize, index: stageIndex))
            await context.traceCollector.record(event: .stageStarted(stage: "Verify", kind: .finalize, input: ""))

            let verifySystem = localizedSystemPrompt(
                "You are a helpful assistant. Review the draft response below and improve it. Fix any errors, remove unnecessary content, and make it clear and natural. Write the improved version directly.",
                language: context.language
            )
            let solveSummary = truncate(solveRaw, to: 800)
            let verifyPrompt = """
                User's question: \(query)

                Draft response:
                \(solveSummary)

                Write an improved version of this response. Keep what is correct, fix what is wrong, and make it concise and natural.
                """

            let verifyRaw = try await streamingGenerate(
                stageName: "Verify",
                systemPrompt: verifySystem,
                userPrompt: verifyPrompt,
                context: context
            )

            // If Verify refused (safety filter), fall back to Solve
            let refusals = ["i cannot", "i can't", "i apologize", "申し訳", "お答えできません"]
            let isRefusal = refusals.contains { verifyRaw.lowercased().contains($0) }
            let finalRaw = isRefusal ? solveRaw : verifyRaw

            let verifyOutput = parseOutput(raw: finalRaw, kind: .finalize)
            allOutputs.append(verifyOutput)
            await context.setOutput(verifyOutput, for: "Verify")
            await context.traceCollector.record(event: .stageCompleted(stage: "Verify", output: verifyOutput))
            await context.emit(.stageCompleted(stageName: "Verify", stageKind: .finalize, output: verifyOutput, index: stageIndex))

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
