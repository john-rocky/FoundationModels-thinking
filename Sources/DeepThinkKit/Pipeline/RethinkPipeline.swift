import Foundation

// MARK: - Rethink Pipeline (Separate Sessions)
// Restate (Session A) → Solve (Session B) → Verify (Session C)
//
// Key technique: each stage uses a fresh LanguageModelSession to avoid
// context pollution — important for on-device models with limited context.

public struct RethinkPipeline: Pipeline, Sendable {
    public let name = "Rethink"
    public let description = "Restate → Solve → Verify (separate sessions)"
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

            // --- Stage 1: Restate (fresh session) ---
            await context.emit(.stageStarted(stageName: "Restate", stageKind: .analyze, index: stageIndex))
            await context.traceCollector.record(event: .stageStarted(stage: "Restate", kind: .analyze, input: query))

            let restateSystem = localizedSystemPrompt(
                "You clarify problems. Restate the problem in simple terms and identify what needs to be found. Be brief.",
                language: context.language
            )
            let restatePrompt = "Restate this problem simply. What do we need to find?\n\nProblem: \(query)\(memoryContext)\(webSearchContext)"

            let restateRaw: String
            do {
                restateRaw = try await streamingGenerate(
                    stageName: "Restate",
                    systemPrompt: restateSystem,
                    userPrompt: restatePrompt,
                    context: context
                )
            } catch let error as ModelError where error.isContextTooLong && !memory.isEmpty {
                restateRaw = try await streamingGenerate(
                    stageName: "Restate",
                    systemPrompt: restateSystem,
                    userPrompt: "Restate this problem simply. What do we need to find?\n\nProblem: \(query)\(webSearchContext)",
                    context: context
                )
            }

            let restateOutput = parseOutput(raw: restateRaw, kind: .analyze)
            allOutputs.append(restateOutput)
            await context.setOutput(restateOutput, for: "Restate")
            await context.traceCollector.record(event: .stageCompleted(stage: "Restate", output: restateOutput))
            await context.emit(.stageCompleted(stageName: "Restate", stageKind: .analyze, output: restateOutput, index: stageIndex))
            stageIndex += 1

            // --- Stage 2: Solve (fresh session, receives analysis) ---
            await context.emit(.stageStarted(stageName: "Solve", stageKind: .solve, index: stageIndex))
            await context.traceCollector.record(event: .stageStarted(stage: "Solve", kind: .solve, input: query))

            let solveSystem = localizedSystemPrompt(
                "You solve problems step by step. Show your work clearly. Always end with 'Answer: [value]'.",
                language: context.language
            )
            let analysis = truncate(restateRaw, to: 600)
            let solvePrompt = "Problem: \(query)\n\nKey information: \(analysis)\n\nSolve step by step. End with 'Answer: [your answer]'"

            let solveRaw = try await streamingGenerate(
                stageName: "Solve",
                systemPrompt: solveSystem,
                userPrompt: solvePrompt,
                context: context
            )

            let solveOutput = parseOutput(raw: solveRaw, kind: .solve)
            allOutputs.append(solveOutput)
            await context.setOutput(solveOutput, for: "Solve")
            await context.traceCollector.record(event: .stageCompleted(stage: "Solve", output: solveOutput))
            await context.emit(.stageCompleted(stageName: "Solve", stageKind: .solve, output: solveOutput, index: stageIndex))
            stageIndex += 1

            // Extract proposed answer from solve stage
            let proposedAnswer = AnswerExtractor.extract(from: solveRaw) ?? truncate(solveRaw, to: 200)

            // --- Stage 3: Verify (fresh session, checks the answer) ---
            await context.emit(.stageStarted(stageName: "Verify", stageKind: .finalize, index: stageIndex))
            await context.traceCollector.record(event: .stageStarted(stage: "Verify", kind: .finalize, input: ""))

            let verifySystem = localizedSystemPrompt(
                "You verify answers to problems. Check the proposed answer carefully. If wrong, provide the correct answer.",
                language: context.language
            )
            let verifyPrompt = """
                Problem: \(query)
                Proposed answer: \(proposedAnswer)

                Check if this answer is correct. Solve the problem again briefly using a different approach. If the answer is correct, confirm it. If wrong, show the correct solution. End with 'Answer: [final answer]'
                """

            let verifyRaw = try await streamingGenerate(
                stageName: "Verify",
                systemPrompt: verifySystem,
                userPrompt: verifyPrompt,
                context: context
            )

            let verifyOutput = parseOutput(raw: verifyRaw, kind: .finalize)
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
