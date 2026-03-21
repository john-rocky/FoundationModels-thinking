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

        var allOutputs: [StageOutput] = []

        // Stage 1: Analyze
        let analyzeInput = await context.buildInput(query: query)
        let analyzeOutput = try await executeWithRetry(
            stage: AnalyzeStage(),
            input: analyzeInput,
            context: context
        )
        allOutputs.append(analyzeOutput)
        await context.setOutput(analyzeOutput, for: "Analyze")

        // Stage 2: Multiple independent Solve runs
        let solveCount = configuration.branchCount
        let solveOutputs = try await withThrowingTaskGroup(
            of: (String, StageOutput).self
        ) { group in
            for i in 0..<solveCount {
                let solveName = "Solve-\(i + 1)"
                let stage = SolveStage(name: solveName)
                let input = await context.buildInput(query: query)

                group.addTask {
                    let output = try await executeWithRetry(
                        stage: stage,
                        input: input,
                        context: context
                    )
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

        // Stage 3: Aggregate
        let aggregateInput = await context.buildInput(query: query)
        let aggregateOutput = try await executeWithRetry(
            stage: AggregateStage(),
            input: aggregateInput,
            context: context
        )
        allOutputs.append(aggregateOutput)
        await context.setOutput(aggregateOutput, for: "Aggregate")

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
