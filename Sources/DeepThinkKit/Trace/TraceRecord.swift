import Foundation

// MARK: - Trace Record

public struct TraceRecord: Sendable, Codable, Identifiable {
    public let id: String
    public let executionId: String
    public let pipelineName: String
    public let stageName: String
    public let stageKind: StageKind
    public let startTime: Date
    public let endTime: Date
    public let input: String
    public let output: String?
    public let memoryHits: [String]
    public let retryCount: Int
    public let error: String?
    public let abortReason: String?
    public let confidence: Double?
    public let metadata: [String: String]

    public var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    public var succeeded: Bool {
        error == nil && output != nil
    }

    public init(
        id: String = UUID().uuidString,
        executionId: String,
        pipelineName: String,
        stageName: String,
        stageKind: StageKind,
        startTime: Date,
        endTime: Date,
        input: String,
        output: String? = nil,
        memoryHits: [String] = [],
        retryCount: Int = 0,
        error: String? = nil,
        abortReason: String? = nil,
        confidence: Double? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.executionId = executionId
        self.pipelineName = pipelineName
        self.stageName = stageName
        self.stageKind = stageKind
        self.startTime = startTime
        self.endTime = endTime
        self.input = input
        self.output = output
        self.memoryHits = memoryHits
        self.retryCount = retryCount
        self.error = error
        self.abortReason = abortReason
        self.confidence = confidence
        self.metadata = metadata
    }
}

// MARK: - Trace Event (for collector)

public enum TraceEvent: Sendable {
    case stageStarted(stage: String, kind: StageKind, input: String)
    case stageCompleted(stage: String, output: StageOutput)
    case stageFailed(stage: String, error: Error)
    case retry(stage: String, attempt: Int, error: Error)
    case memoryRetrieved(stage: String, entries: [MemoryEntry])
    case memorySaved(stage: String, entry: MemoryEntry)
    case pipelineStarted(name: String, query: String)
    case pipelineCompleted(name: String, duration: TimeInterval)
    case pipelineAborted(name: String, reason: String)
}
