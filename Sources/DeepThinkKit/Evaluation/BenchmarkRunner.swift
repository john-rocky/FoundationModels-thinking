import Foundation

// MARK: - Benchmark Result

public struct BenchmarkResult: Sendable, Identifiable {
    public let id: String
    public let problemId: String
    public let problemQuestion: String
    public let expectedAnswer: String
    public let pipelineKind: PipelineKind
    public let extractedAnswer: String?
    public let isCorrect: Bool
    public let fullOutput: String
    public let latency: TimeInterval
    public let confidence: Double
    public let errorMessage: String?

    public init(
        id: String = UUID().uuidString,
        problemId: String,
        problemQuestion: String,
        expectedAnswer: String,
        pipelineKind: PipelineKind,
        extractedAnswer: String?,
        isCorrect: Bool,
        fullOutput: String,
        latency: TimeInterval,
        confidence: Double,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.problemId = problemId
        self.problemQuestion = problemQuestion
        self.expectedAnswer = expectedAnswer
        self.pipelineKind = pipelineKind
        self.extractedAnswer = extractedAnswer
        self.isCorrect = isCorrect
        self.fullOutput = fullOutput
        self.latency = latency
        self.confidence = confidence
        self.errorMessage = errorMessage
    }
}

// MARK: - Benchmark Report

public struct BenchmarkReport: Sendable {
    public let results: [BenchmarkResult]
    public let pipelineAccuracies: [PipelineKind: Double]
    public let pipelineLatencies: [PipelineKind: TimeInterval]
    public let totalDuration: TimeInterval

    public init(results: [BenchmarkResult]) {
        self.results = results

        var accuracies: [PipelineKind: Double] = [:]
        var latencies: [PipelineKind: TimeInterval] = [:]
        let grouped = Dictionary(grouping: results, by: \.pipelineKind)

        for (kind, groupResults) in grouped {
            let correct = groupResults.filter(\.isCorrect).count
            accuracies[kind] = Double(correct) / Double(groupResults.count)
            latencies[kind] = groupResults.reduce(0) { $0 + $1.latency }
                / Double(groupResults.count)
        }

        self.pipelineAccuracies = accuracies
        self.pipelineLatencies = latencies
        self.totalDuration = results.reduce(0) { $0 + $1.latency }
    }

    public func results(for kind: PipelineKind) -> [BenchmarkResult] {
        results.filter { $0.pipelineKind == kind }
    }

    public func result(for problemId: String, pipeline: PipelineKind) -> BenchmarkResult? {
        results.first { $0.problemId == problemId && $0.pipelineKind == pipeline }
    }
}

// MARK: - Benchmark Runner

public actor BenchmarkRunner {
    public init() {}

    public func run(
        problems: [BenchmarkProblem],
        pipelineKinds: [PipelineKind],
        modelProvider: any ModelProvider,
        onProgress: @Sendable @MainActor (String, Int, Int) -> Void
    ) async -> BenchmarkReport {
        var allResults: [BenchmarkResult] = []
        let total = problems.count * pipelineKinds.count
        var completed = 0

        for kind in pipelineKinds {
            let pipeline = PipelineFactory.create(kind: kind)

            for problem in problems {
                completed += 1
                await onProgress(
                    "\(kind.displayName): \(problem.id)",
                    completed,
                    total
                )

                let startTime = Date.now
                var fullOutput = ""
                var extractedAnswer: String?
                var confidence = 0.5
                var errorMsg: String?

                do {
                    let context = PipelineContext(
                        modelProvider: modelProvider,
                        language: AppLanguage.detect(from: problem.question)
                    )
                    let pipelineResult = try await pipeline.execute(
                        query: problem.question,
                        context: context
                    )
                    fullOutput = pipelineResult.finalOutput.content
                    extractedAnswer = AnswerExtractor.extract(from: fullOutput)
                    confidence = pipelineResult.finalOutput.confidence
                } catch {
                    if let se = error as? StageError {
                        errorMsg = se.errorDescription ?? "\(se)"
                    } else {
                        errorMsg = "\(error)"
                    }
                }

                let elapsed = Date.now.timeIntervalSince(startTime)
                let isCorrect = AnswerMatcher.matches(
                    actual: extractedAnswer,
                    expected: problem.expectedAnswer,
                    acceptableAnswers: problem.acceptableAnswers
                )

                let benchResult = BenchmarkResult(
                    problemId: problem.id,
                    problemQuestion: problem.question,
                    expectedAnswer: problem.expectedAnswer,
                    pipelineKind: kind,
                    extractedAnswer: extractedAnswer,
                    isCorrect: isCorrect,
                    fullOutput: fullOutput,
                    latency: elapsed,
                    confidence: confidence,
                    errorMessage: errorMsg
                )
                allResults.append(benchResult)
            }
        }

        return BenchmarkReport(results: allResults)
    }
}
