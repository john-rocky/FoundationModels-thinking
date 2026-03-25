import Foundation

// MARK: - Self-Consistency Pipeline
// Analyze -> Multi Solve -> Aggregate -> Finalize

public struct SelfConsistencyPipeline: Pipeline, Sendable {
    public let name = "SelfConsistency"
    public let description = "Analyze → Multi-Solve → Aggregate → Finalize"
    public let configuration: PipelineConfiguration

    public var stages: [any Stage] {
        var s: [any Stage] = [AnalyzeStage()]
        for i in 0..<configuration.branchCount {
            s.append(SolveStage(name: "Solve-\(i + 1)"))
        }
        s.append(AggregateStage())
        s.append(FinalizeStage())
        return s
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

        // Analyze + parallel solves (counted as 1) + Aggregate + Finalize
        let searchStageCount = configuration.webSearchEnabled ? 1 : 0
        await context.emit(.pipelineStarted(pipelineName: name, stageCount: 4 + searchStageCount))

        var allOutputs: [StageOutput] = []
        var stageIndex = 0

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

            // Stage 2: Multiple independent Solve runs
            let solveCount = configuration.branchCount
            let branchNames = (0..<solveCount).map { "Solve-\($0 + 1)" }
            await context.emit(.branchesStarted(branchNames: branchNames))

            let solveOutputs = try await withThrowingTaskGroup(
                of: (String, StageOutput).self
            ) { group in
                for i in 0..<solveCount {
                    let solveName = branchNames[i]
                    let stage = SolveStage(name: solveName)
                    let input = await context.buildInput(query: query)

                    group.addTask {
                        let output = try await executeWithRetry(
                            stage: stage,
                            input: input,
                            context: context
                        )
                        await context.emit(.branchCompleted(branchName: solveName, output: output))
                        return (solveName, output)
                    }
                }

                var results: [(String, StageOutput)] = []
                for try await result in group {
                    results.append(result)
                }
                return results.sorted { $0.0 < $1.0 }
            }

            for (solveName, output) in solveOutputs {
                allOutputs.append(output)
                await context.setOutput(output, for: solveName)
            }
            stageIndex += 1

            // Stage 3: Aggregate
            await context.emit(.stageStarted(stageName: "Aggregate", stageKind: .aggregate, index: stageIndex))
            let aggregateInput = await context.buildInput(query: query)
            let aggregateOutput = try await executeWithRetry(
                stage: AggregateStage(),
                input: aggregateInput,
                context: context
            )
            allOutputs.append(aggregateOutput)
            await context.setOutput(aggregateOutput, for: "Aggregate")
            await context.emit(.stageCompleted(stageName: "Aggregate", stageKind: .aggregate, output: aggregateOutput, index: stageIndex))
            stageIndex += 1

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
