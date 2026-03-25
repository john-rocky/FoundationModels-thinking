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

        // Analyze + parallel branches (counted as 1) + Merge + Finalize
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

            // Stage 2: Parallel Solve branches
            let branchCount = configuration.branchCount
            let branchNames = (0..<branchCount).map { "Solve-\(Character(UnicodeScalar(65 + $0)!))" }
            await context.emit(.branchesStarted(branchNames: branchNames))

            let branchOutputs = try await withThrowingTaskGroup(
                of: (String, StageOutput).self
            ) { group in
                for i in 0..<branchCount {
                    let branchName = branchNames[i]
                    let stage = SolveStage(name: branchName)
                    let input = await context.buildInput(query: query)

                    group.addTask {
                        let output = try await executeWithRetry(
                            stage: stage,
                            input: input,
                            context: context
                        )
                        await context.emit(.branchCompleted(branchName: branchName, output: output))
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
            stageIndex += 1

            // Stage 3: Merge
            await context.emit(.stageStarted(stageName: "Merge", stageKind: .merge, index: stageIndex))
            let mergeInput = await context.buildInput(query: query)
            let mergeOutput = try await executeWithRetry(
                stage: MergeStage(),
                input: mergeInput,
                context: context
            )
            allOutputs.append(mergeOutput)
            await context.setOutput(mergeOutput, for: "Merge")
            await context.emit(.stageCompleted(stageName: "Merge", stageKind: .merge, output: mergeOutput, index: stageIndex))
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
