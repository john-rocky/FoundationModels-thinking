import Foundation

// MARK: - Direct Pipeline (Single-Pass)
// Query -> Response (no multi-stage reasoning)

public struct DirectPipeline: Pipeline, Sendable {
    public let name = "Direct"
    public let description = "Query -> Response (単一推論、パイプラインなし)"
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

        await context.traceCollector.record(
            event: .stageStarted(stage: "Direct", kind: .solve, input: query)
        )

        let raw = try await context.modelProvider.generate(
            systemPrompt: "質問に対して正確で分かりやすい回答を生成してください。",
            userPrompt: query
        )

        let output = StageOutput(
            stageKind: .solve,
            content: raw,
            confidence: 0.5,
            metadata: ["mode": "direct"]
        )

        await context.traceCollector.record(
            event: .stageCompleted(stage: "Direct", output: output)
        )

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
            finalOutput: output,
            stageOutputs: [output],
            trace: trace,
            startTime: startTime,
            endTime: endTime
        )
    }
}
