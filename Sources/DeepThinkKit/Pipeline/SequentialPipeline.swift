import Foundation

// MARK: - Sequential Pipeline
// Analyze -> Plan -> Solve -> Finalize

public struct SequentialPipeline: Pipeline, Sendable {
    public let name = "Sequential"
    public let description = "Analyze → Plan → Solve → Finalize sequential pipeline"
    public let configuration: PipelineConfiguration

    public var stages: [any Stage] {
        [AnalyzeStage(), PlanStage(), SolveStage(), FinalizeStage()]
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
        await context.emit(.pipelineStarted(pipelineName: name, stageCount: stages.count))

        var allOutputs: [StageOutput] = []

        do {
            for (index, stage) in stages.enumerated() {
                guard index < configuration.maxStages else {
                    break
                }

                await context.emit(.stageStarted(stageName: stage.name, stageKind: stage.kind, index: index))

                let input = await context.buildInput(query: query)
                let output = try await executeWithRetry(
                    stage: stage,
                    input: input,
                    context: context
                )

                allOutputs.append(output)
                await context.setOutput(output, for: stage.name)
                await context.emit(.stageCompleted(stageName: stage.name, stageKind: stage.kind, output: output, index: index))
            }
        } catch {
            await context.emit(.pipelineFailed(error: "\(error)"))
            await context.finishEventStream()
            throw error
        }

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
