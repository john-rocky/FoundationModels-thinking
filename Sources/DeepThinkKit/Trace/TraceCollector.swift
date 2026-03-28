import Foundation

// MARK: - Trace Collector

public actor TraceCollector {
    private var records: [TraceRecord] = []
    private var currentPipeline: String = ""
    private var executionId: String = ""
    private var pendingStages: [String: (start: Date, input: String)] = [:]

    public init() {}

    public func setPipeline(name: String, executionId: String) {
        self.currentPipeline = name
        self.executionId = executionId
    }

    public func record(event: TraceEvent) {
        switch event {
        case .stageStarted(let stage, _, let input):
            pendingStages[stage] = (start: .now, input: input)

        case .stageCompleted(let stage, let output):
            guard let pending = pendingStages.removeValue(forKey: stage) else { return }
            let record = TraceRecord(
                executionId: executionId,
                pipelineName: currentPipeline,
                stageName: stage,
                stageKind: output.stageKind,
                startTime: pending.start,
                endTime: .now,
                input: pending.input,
                output: output.content,
                confidence: output.confidence
            )
            records.append(record)

        case .stageFailed(let stage, let error):
            guard let pending = pendingStages.removeValue(forKey: stage) else { return }
            let record = TraceRecord(
                executionId: executionId,
                pipelineName: currentPipeline,
                stageName: stage,
                stageKind: .custom,
                startTime: pending.start,
                endTime: .now,
                input: pending.input,
                error: error.localizedDescription
            )
            records.append(record)

        case .retry(let stage, let attempt, _):
            if var last = records.last, last.stageName == stage {
                records.removeLast()
                last = TraceRecord(
                    id: last.id,
                    executionId: last.executionId,
                    pipelineName: last.pipelineName,
                    stageName: last.stageName,
                    stageKind: last.stageKind,
                    startTime: last.startTime,
                    endTime: last.endTime,
                    input: last.input,
                    output: last.output,
                    memoryHits: last.memoryHits,
                    retryCount: attempt,
                    error: last.error,
                    confidence: last.confidence
                )
                records.append(last)
            }

        case .memoryRetrieved(let stage, let entries):
            if var last = records.last, last.stageName == stage {
                records.removeLast()
                last = TraceRecord(
                    id: last.id,
                    executionId: last.executionId,
                    pipelineName: last.pipelineName,
                    stageName: last.stageName,
                    stageKind: last.stageKind,
                    startTime: last.startTime,
                    endTime: last.endTime,
                    input: last.input,
                    output: last.output,
                    memoryHits: entries.map(\.content),
                    retryCount: last.retryCount,
                    error: last.error,
                    confidence: last.confidence
                )
                records.append(last)
            }

        case .memorySaved, .pipelineStarted, .pipelineCompleted, .pipelineAborted:
            break
        }
    }

    public func allRecords() -> [TraceRecord] {
        records
    }

    public func records(for stage: String) -> [TraceRecord] {
        records.filter { $0.stageName == stage }
    }

    public func reset() {
        records.removeAll()
        pendingStages.removeAll()
    }
}
