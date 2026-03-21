import Foundation

// MARK: - Strategy Comparator

public actor StrategyComparator {
    private var results: [String: [PipelineResult]] = [:]

    public init() {}

    public func compare(
        query: String,
        pipelines: [any Pipeline],
        modelProvider: any ModelProvider,
        memoryPolicy: MemoryPolicy = .default
    ) async throws -> ComparisonResult {
        var pipelineResults: [(String, EvaluationMetrics)] = []

        for pipeline in pipelines {
            let context = PipelineContext(modelProvider: modelProvider)
            let result = try await pipeline.execute(query: query, context: context)

            let metrics = EvaluationMetrics(from: result)
            pipelineResults.append((pipeline.name, metrics))

            if results[pipeline.name] == nil {
                results[pipeline.name] = []
            }
            results[pipeline.name]?.append(result)
        }

        return ComparisonResult(results: pipelineResults)
    }

    public func compareWithMemory(
        query: String,
        pipeline: any Pipeline,
        modelProvider: any ModelProvider
    ) async throws -> ComparisonResult {
        // Without memory
        let noMemoryContext = PipelineContext(modelProvider: modelProvider)
        let noMemoryResult = try await pipeline.execute(query: query, context: noMemoryContext)
        let noMemoryMetrics = EvaluationMetrics(from: noMemoryResult)

        // With memory
        let withMemoryContext = PipelineContext(modelProvider: modelProvider)
        let withMemoryResult = try await pipeline.execute(query: query, context: withMemoryContext)
        let withMemoryMetrics = EvaluationMetrics(from: withMemoryResult)

        return ComparisonResult(results: [
            ("\(pipeline.name) (no memory)", noMemoryMetrics),
            ("\(pipeline.name) (with memory)", withMemoryMetrics),
        ])
    }

    public func history(for pipeline: String) -> [PipelineResult] {
        results[pipeline] ?? []
    }

    public func clearHistory() {
        results.removeAll()
    }
}
