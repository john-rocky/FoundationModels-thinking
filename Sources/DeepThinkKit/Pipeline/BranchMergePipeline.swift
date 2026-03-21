import Foundation

// MARK: - Branch and Merge Pipeline
// Analyze -> {Solve A, Solve B, Solve C} -> Merge -> Finalize

public struct BranchMergePipeline: Pipeline, Sendable {
    public let name = "BranchMerge"
    public let description = "Analyze → {Solve A, B, C} → Merge → Finalize"
    public let configuration: PipelineConfiguration

    public var stages: [any Stage] {
        var s: [any Stage] = [AnalyzeStage()]
        for i in 0..<configuration.branchCount {
            s.append(SolveStage(name: "Solve-\(Character(UnicodeScalar(65 + i)!))"))
        }
        s.append(MergeStage())
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

        // Stage 2: Parallel Solve branches
        let branchCount = configuration.branchCount
        let branchOutputs = try await withThrowingTaskGroup(
            of: (String, StageOutput).self
        ) { group in
            for i in 0..<branchCount {
                let branchName = "Solve-\(Character(UnicodeScalar(65 + i)!))"
                let stage = SolveStage(name: branchName)
                let input = await context.buildInput(query: query)

                group.addTask {
                    let output = try await executeWithRetry(
                        stage: stage,
                        input: input,
                        context: context
                    )
                    return (branchName, output)
                }
            }

            var results: [(String, StageOutput)] = []
            for try await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }
        }

        for (branchName, output) in branchOutputs {
            allOutputs.append(output)
            await context.setOutput(output, for: branchName)
        }

        // Stage 3: Merge
        let mergeInput = await context.buildInput(query: query)
        let mergeOutput = try await executeWithRetry(
            stage: MergeStage(),
            input: mergeInput,
            context: context
        )
        allOutputs.append(mergeOutput)
        await context.setOutput(mergeOutput, for: "Merge")

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
