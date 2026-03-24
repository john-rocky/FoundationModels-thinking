import Foundation

// MARK: - Direct Pipeline (Single-Pass)
// Query -> Response (no multi-stage reasoning)

public struct DirectPipeline: Pipeline, Sendable {
    public let name = "Direct"
    public let description = "Query -> Response (single inference, no pipeline)"
    public let configuration: PipelineConfiguration

    public var stages: [any Stage] { [] }

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
        await context.emit(.pipelineStarted(pipelineName: name, stageCount: 1))

        await context.traceCollector.record(
            event: .stageStarted(stage: "Direct", kind: .solve, input: query)
        )
        await context.emit(.stageStarted(stageName: "Direct", stageKind: .solve, index: 0))

        let raw: String
        do {
            raw = try await context.modelProvider.generate(
                systemPrompt: nil,
                userPrompt: query
            )
        } catch {
            let stageError: Error
            if case ModelError.safetyFilterViolation = error {
                stageError = StageError.contentFiltered(stage: "Direct")
            } else {
                stageError = error
            }
            await context.emit(.stageFailed(stageName: "Direct", error: "\(stageError)"))
            await context.emit(.pipelineFailed(error: "\(stageError)"))
            await context.finishEventStream()
            throw stageError
        }

        let output = StageOutput(
            stageKind: .solve,
            content: raw,
            confidence: 0.5,
            metadata: ["mode": "direct"]
        )

        await context.traceCollector.record(
            event: .stageCompleted(stage: "Direct", output: output)
        )
        await context.emit(.stageCompleted(stageName: "Direct", stageKind: .solve, output: output, index: 0))

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
            finalOutput: output,
            stageOutputs: [output],
            trace: trace,
            startTime: startTime,
            endTime: endTime
        )

        await context.emit(.pipelineCompleted(result: result))
        await context.finishEventStream()

        return result
    }
}
