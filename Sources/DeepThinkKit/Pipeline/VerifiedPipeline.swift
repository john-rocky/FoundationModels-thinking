import Foundation

// MARK: - Verified Pipeline
// Extract Constraints -> Deterministic Solve -> Explain

@available(iOS 26.0, macOS 26.0, *)
public struct VerifiedPipeline: Pipeline, Sendable {
    public let name = "Verified"
    public let description = "Extract → Solve (deterministic) → Explain"
    public let configuration: PipelineConfiguration

    public var stages: [any Stage] {
        [ExtractConstraintsStage(), DeterministicSolveStage(), ExplainStage()]
    }

    public init(configuration: PipelineConfiguration = .default) {
        self.configuration = configuration
    }

    public func execute(query: String, context: PipelineContext) async throws -> PipelineResult {
        let startTime = Date.now
        await context.traceCollector.setPipeline(
            name: name,
            executionId: context.executionId
        )
        await context.traceCollector.record(
            event: .pipelineStarted(name: name, query: query)
        )
        let searchStageCount = configuration.webSearchEnabled ? 1 : 0
        await context.emit(.pipelineStarted(pipelineName: name, stageCount: 3 + searchStageCount))

        var allOutputs: [StageOutput] = []
        var stageIndex = 0

        do {
            // Optional: Web Search
            var webSearchContext = ""
            if let wsOutput = try await executeWebSearchIfEnabled(
                query: query, context: context, configuration: configuration,
                allOutputs: &allOutputs, stageIndex: &stageIndex
            ), wsOutput.metadata["searchDecision"] == "searched" {
                webSearchContext = "\n\n\(truncate(wsOutput.content, to: configuration.webSearchContextBudget))"
            }

            // Stage: Extract constraints (LLM)
            await context.emit(.stageStarted(stageName: "Extract", stageKind: .analyze, index: stageIndex))
            let extractInput = await context.buildInput(query: query + webSearchContext)
            let extractOutput = try await executeWithRetry(
                stage: ExtractConstraintsStage(),
                input: extractInput,
                context: context
            )
            allOutputs.append(extractOutput)
            await context.setOutput(extractOutput, for: "Extract")
            await context.emit(.stageCompleted(stageName: "Extract", stageKind: .analyze, output: extractOutput, index: stageIndex))
            stageIndex += 1

            // Stage: Deterministic solve (no LLM)
            await context.emit(.stageStarted(stageName: "Solve", stageKind: .solve, index: stageIndex))
            let solveInput = await context.buildInput(query: query)
            let solveOutput = try await DeterministicSolveStage().execute(input: solveInput, context: context)
            allOutputs.append(solveOutput)
            await context.setOutput(solveOutput, for: "Solve")
            await context.emit(.stageCompleted(stageName: "Solve", stageKind: .solve, output: solveOutput, index: stageIndex))
            stageIndex += 1

            // Stage: Explain (LLM)
            await context.emit(.stageStarted(stageName: "Explain", stageKind: .finalize, index: stageIndex))
            let explainInput = await context.buildInput(query: query)
            let explainOutput = try await executeWithRetry(
                stage: ExplainStage(),
                input: explainInput,
                context: context
            )
            allOutputs.append(explainOutput)
            await context.emit(.stageCompleted(stageName: "Explain", stageKind: .finalize, output: explainOutput, index: stageIndex))

            let endTime = Date.now
            let trace = await context.traceCollector.allRecords()

            await context.traceCollector.record(
                event: .pipelineCompleted(name: name, duration: endTime.timeIntervalSince(startTime))
            )

            let result = PipelineResult(
                pipelineName: name,
                query: query,
                finalOutput: explainOutput,
                stageOutputs: allOutputs,
                trace: trace,
                startTime: startTime,
                endTime: endTime
            )

            await context.emit(.pipelineCompleted(result: result))
            await context.finishEventStream()

            return result

        } catch {
            await context.emit(.pipelineFailed(error: "\(error)"))
            await context.finishEventStream()
            throw error
        }
    }
}
