import Foundation

// MARK: - Evaluation Metrics

public struct EvaluationMetrics: Sendable, Codable {
    public let pipelineName: String
    public let completionRate: Double
    public let parseSuccessRate: Double
    public let averageConfidence: Double
    public let totalLatency: TimeInterval
    public let stageLatencies: [String: TimeInterval]
    public let memoryHitRate: Double
    public let critiqueImprovementRate: Double
    public let loopDivergenceRate: Double
    public let stageCount: Int

    public init(from result: PipelineResult) {
        self.pipelineName = result.pipelineName
        self.completionRate = result.success ? 1.0 : 0.0
        self.totalLatency = result.totalDuration
        self.stageCount = result.stageOutputs.count

        let confidences = result.stageOutputs.map(\.confidence)
        self.averageConfidence = confidences.isEmpty
            ? 0.0
            : confidences.reduce(0, +) / Double(confidences.count)

        self.parseSuccessRate = result.stageOutputs.isEmpty
            ? 0.0
            : Double(result.stageOutputs.filter { !$0.content.isEmpty }.count) /
              Double(result.stageOutputs.count)

        var latencies: [String: TimeInterval] = [:]
        for record in result.trace {
            latencies[record.stageName] = record.duration
        }
        self.stageLatencies = latencies

        let memoryStages = result.trace.filter { !$0.memoryHits.isEmpty }
        self.memoryHitRate = result.trace.isEmpty
            ? 0.0
            : Double(memoryStages.count) / Double(result.trace.count)

        let critiqueOutputs = result.stageOutputs.filter { $0.stageKind == .critique }
        let reviseOutputs = result.stageOutputs.filter { $0.stageKind == .revise }
        if !critiqueOutputs.isEmpty && !reviseOutputs.isEmpty {
            let improved = zip(critiqueOutputs, reviseOutputs).filter {
                $0.1.confidence > $0.0.confidence
            }.count
            self.critiqueImprovementRate = Double(improved) / Double(critiqueOutputs.count)
        } else {
            self.critiqueImprovementRate = 0.0
        }

        self.loopDivergenceRate = 0.0
    }
}

// MARK: - Comparison Result

public struct ComparisonResult: Sendable {
    public let results: [(pipeline: String, metrics: EvaluationMetrics)]
    public let winner: String?

    public init(results: [(String, EvaluationMetrics)]) {
        self.results = results.map { (pipeline: $0.0, metrics: $0.1) }
        self.winner = results
            .max { $0.1.averageConfidence < $1.1.averageConfidence }?
            .0
    }
}
