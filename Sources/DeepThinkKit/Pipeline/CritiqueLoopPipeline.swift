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

        // Stage count: Analyze + Solve + (Critique + Revise) * maxLoops + Finalize
        let searchStageCount = configuration.webSearchEnabled ? 1 : 0
        let estimatedStageCount = 2 + configuration.maxCritiqueReviseLoops * 2 + 1 + searchStageCount
        await context.emit(.pipelineStarted(pipelineName: name, stageCount: estimatedStageCount))

        var allOutputs: [StageOutput] = []
        var stageIndex = 0
        let checker = ConvergenceChecker(
            policy: LoopPolicy(
                maxIterations: configuration.maxCritiqueReviseLoops,
                convergenceThreshold: configuration.convergenceThreshold,
                confidenceTarget: configuration.confidenceThreshold
            )
        )

        do {
            // Optional: Web Search
            let _ = try await executeWebSearchIfEnabled(
                query: query, context: context, configuration: configuration,
                allOutputs: &allOutputs, stageIndex: &stageIndex
            )

            // Stage: Analyze
            await context.emit(.stageStarted(stageName: "Analyze", stageKind: .analyze, index: stageIndex))
            let analyzeInput = await context.buildInput(query: query)
            let analyzeOutput = try await executeWithRetry(
                stage: AnalyzeStage(),
                input: analyzeInput,
                context: context
            )
            allOutputs.append(analyzeOutput)
            await context.setOutput(analyzeOutput, for: "Analyze")
            await context.emit(.stageCompleted(stageName: "Analyze", stageKind: .analyze, output: analyzeOutput, index: stageIndex))
            stageIndex += 1

            // Stage 2: Solve
            await context.emit(.stageStarted(stageName: "Solve", stageKind: .solve, index: stageIndex))
            let solveInput = await context.buildInput(query: query)
            let solveOutput = try await executeWithRetry(
                stage: SolveStage(),
                input: solveInput,
                context: context
            )
            allOutputs.append(solveOutput)
            await context.setOutput(solveOutput, for: "Solve")
            await context.emit(.stageCompleted(stageName: "Solve", stageKind: .solve, output: solveOutput, index: stageIndex))
            stageIndex += 1

            // Stage 3: Critique -> Revise loop
            var previousConfidence = solveOutput.confidence
            var bestOutput = solveOutput

            for iteration in 1...configuration.maxCritiqueReviseLoops {
                await context.emit(.loopIterationStarted(iteration: iteration, maxIterations: configuration.maxCritiqueReviseLoops))

                // Critique
                await context.emit(.stageStarted(stageName: "Critique", stageKind: .critique, index: stageIndex))
                let critiqueInput = await context.buildInput(query: query)
                let critiqueOutput = try await executeWithRetry(
                    stage: CritiqueStage(),
                    input: critiqueInput,
                    context: context
                )
                allOutputs.append(critiqueOutput)
                await context.setOutput(critiqueOutput, for: "Critique")
                await context.emit(.stageCompleted(stageName: "Critique", stageKind: .critique, output: critiqueOutput, index: stageIndex))
                stageIndex += 1

                // Revise
                await context.emit(.stageStarted(stageName: "Revise", stageKind: .revise, index: stageIndex))
                let reviseInput = await context.buildInput(query: query)
                let reviseOutput = try await executeWithRetry(
                    stage: ReviseStage(),
                    input: reviseInput,
                    context: context
                )
                allOutputs.append(reviseOutput)
                await context.setOutput(reviseOutput, for: "Revise")
                await context.emit(.stageCompleted(stageName: "Revise", stageKind: .revise, output: reviseOutput, index: stageIndex))
                stageIndex += 1

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
                    await context.setOutput(reviseOutput, for: "Solve")
                case .stop(let reason):
                    if reason == .degradation {
                        await context.setOutput(bestOutput, for: "Revise")
                    }
                    let reasonStr = "\(reason)"
                    await context.emit(.loopEnded(reason: reasonStr))
                    break
                }

                if case .stop = decision { break }
            }

            // Stage 4: Finalize
            await context.emit(.stageStarted(stageName: "Finalize", stageKind: .finalize, index: stageIndex))
            let finalizeInput = await context.buildInput(query: query)
            let finalizeOutput = try await executeWithRetry(
                stage: FinalizeStage(),
                input: finalizeInput,
                context: context
            )
            allOutputs.append(finalizeOutput)
            await context.emit(.stageCompleted(stageName: "Finalize", stageKind: .finalize, output: finalizeOutput, index: stageIndex))

            let endTime = Date.now
            let trace = await context.traceCollector.allRecords()

            await context.traceCollector.record(
                event: .pipelineCompleted(
                    name: name,
                    duration: endTime.timeIntervalSince(startTime)
                )
            )

            let result = PipelineResult(
                pipelineName: name,
                query: query,
                finalOutput: finalizeOutput,
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
