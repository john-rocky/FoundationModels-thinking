import Foundation

// MARK: - Critique Loop Pipeline
// Analyze -> Solve -> (Critique -> Revise) x N -> Finalize

public struct CritiqueLoopPipeline: Pipeline, Sendable {
    public let name = "CritiqueLoop"
    public let description = "Analyze → Solve → (Critique → Revise) x N → Finalize"
    public let configuration: PipelineConfiguration

    public var stages: [any Stage] {
        [AnalyzeStage(), SolveStage(), CritiqueStage(), ReviseStage(), FinalizeStage()]
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

        var allOutputs: [StageOutput] = []
        let checker = ConvergenceChecker(
            policy: LoopPolicy(
                maxIterations: configuration.maxCritiqueReviseLoops,
                convergenceThreshold: configuration.convergenceThreshold,
                confidenceTarget: configuration.confidenceThreshold
            )
        )

        // Stage 1: Analyze
        let analyzeInput = await context.buildInput(query: query)
        let analyzeOutput = try await executeWithRetry(
            stage: AnalyzeStage(),
            input: analyzeInput,
            context: context
        )
        allOutputs.append(analyzeOutput)
        await context.setOutput(analyzeOutput, for: "Analyze")

        // Stage 2: Solve
        let solveInput = await context.buildInput(query: query)
        let solveOutput = try await executeWithRetry(
            stage: SolveStage(),
            input: solveInput,
            context: context
        )
        allOutputs.append(solveOutput)
        await context.setOutput(solveOutput, for: "Solve")

        // Stage 3: Critique -> Revise loop
        var previousConfidence = solveOutput.confidence
        var bestOutput = solveOutput

        for iteration in 1...configuration.maxCritiqueReviseLoops {
            // Critique
            let critiqueInput = await context.buildInput(query: query)
            let critiqueOutput = try await executeWithRetry(
                stage: CritiqueStage(),
                input: critiqueInput,
                context: context
            )
            allOutputs.append(critiqueOutput)
            await context.setOutput(critiqueOutput, for: "Critique")

            // Revise
            let reviseInput = await context.buildInput(query: query)
            let reviseOutput = try await executeWithRetry(
                stage: ReviseStage(),
                input: reviseInput,
                context: context
            )
            allOutputs.append(reviseOutput)
            await context.setOutput(reviseOutput, for: "Revise")

            let decision = checker.shouldContinue(
                iteration: iteration,
                previousConfidence: previousConfidence,
                currentConfidence: reviseOutput.confidence
            )

            await context.traceCollector.record(
                event: .loopDecision(stage: "CritiqueLoop", decision: decision)
            )

            if reviseOutput.confidence > bestOutput.confidence {
                bestOutput = reviseOutput
            }

            switch decision {
            case .continue:
                previousConfidence = reviseOutput.confidence
                // Update Solve output with revised version for next iteration
                await context.setOutput(reviseOutput, for: "Solve")
            case .stop(let reason):
                if reason == .degradation {
                    // Rollback: use best output so far
                    await context.setOutput(bestOutput, for: "Revise")
                }
                break
            }

            if case .stop = decision { break }
        }

        // Stage 4: Finalize
        let finalizeInput = await context.buildInput(query: query)
        let finalizeOutput = try await executeWithRetry(
            stage: FinalizeStage(),
            input: finalizeInput,
            context: context
        )
        allOutputs.append(finalizeOutput)

        let endTime = Date.now
        let trace = await context.traceCollector.allRecords()

        await context.traceCollector.record(
            event: .pipelineCompleted(
                name: name,
                duration: endTime.timeIntervalSince(startTime)
            )
        )

        return PipelineResult(
            pipelineName: name,
            query: query,
            finalOutput: finalizeOutput,
            stageOutputs: allOutputs,
            trace: trace,
            startTime: startTime,
            endTime: endTime
        )
    }
}
