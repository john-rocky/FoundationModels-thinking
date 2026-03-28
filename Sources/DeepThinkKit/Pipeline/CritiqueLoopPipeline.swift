import Foundation

// MARK: - Critique Loop Pipeline
// Solve (session A) -> Critique (session B) -> Finalize (session C)

public struct CritiqueLoopPipeline: Pipeline, Sendable {
    public let name = "CritiqueLoop"
    public let description = "Solve → Critique → Final (separate sessions)"
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

            // Build memory + conversation context
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
                    userPrompt: "Solve this problem step by step. End with 'Answer: [your answer]'\n\nProblem: \(query)\(webSearchContext)",
                    context: context
                )
            }

            let solveOutput = parseOutput(raw: solveRaw, kind: .solve)
            allOutputs.append(solveOutput)
            await context.setOutput(solveOutput, for: "Solve")
            await context.traceCollector.record(event: .stageCompleted(stage: "Solve", output: solveOutput))
            await context.emit(.stageCompleted(stageName: "Solve", stageKind: .solve, output: solveOutput, index: stageIndex))
            stageIndex += 1

            // --- Stage 2: Critique (fresh session, reviews the solve output) ---
            await context.emit(.stageStarted(stageName: "Critique", stageKind: .critique, index: stageIndex))
            await context.traceCollector.record(event: .stageStarted(stage: "Critique", kind: .critique, input: ""))

            let critiqueSystem = localizedSystemPrompt(
                "You review answers to problems. Find errors if any exist.",
                language: context.language
            )
            let solveAnswer = truncate(solveRaw, to: 600)
            let critiquePrompt = """
                Problem: \(query)

                Proposed solution:
                \(solveAnswer)

                Check this solution for these specific issues:
                1. Re-read the problem wording carefully. Was the problem interpreted correctly?
                2. Are all calculations correct? Redo the math.
                3. Does the answer make sense?
                If you find an error, explain what is wrong. If correct, say "No issues found."
                """

            let critiqueRaw = try await streamingGenerate(
                stageName: "Critique",
                systemPrompt: critiqueSystem,
                userPrompt: critiquePrompt,
                context: context
            )

            let critiqueOutput = parseOutput(raw: critiqueRaw, kind: .critique)
            allOutputs.append(critiqueOutput)
            await context.setOutput(critiqueOutput, for: "Critique")
            await context.traceCollector.record(event: .stageCompleted(stage: "Critique", output: critiqueOutput))
            await context.emit(.stageCompleted(stageName: "Critique", stageKind: .critique, output: critiqueOutput, index: stageIndex))
            stageIndex += 1

            // --- Stage 3: Finalize (fresh session, produces corrected answer) ---
            await context.emit(.stageStarted(stageName: "Finalize", stageKind: .finalize, index: stageIndex))
            await context.traceCollector.record(event: .stageStarted(stage: "Finalize", kind: .finalize, input: ""))

            let finalSystem = localizedSystemPrompt(
                "You write final answers to problems. Be clear and correct. Always end with 'Answer: [value]'.",
                language: context.language
            )
            let critique = truncate(critiqueRaw, to: 400)
            let finalPrompt = """
                Problem: \(query)

                Initial solution:
                \(solveAnswer)

                Review feedback:
                \(critique)

                Write the final corrected answer. Fix any issues found in the review. If no errors were found, restate the answer. End with 'Answer: [your answer]'
                """

            let finalRaw = try await streamingGenerate(
                stageName: "Finalize",
                systemPrompt: finalSystem,
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
