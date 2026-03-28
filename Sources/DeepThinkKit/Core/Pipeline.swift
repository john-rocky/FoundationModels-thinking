import Foundation

// MARK: - Pipeline Configuration

public struct PipelineConfiguration: Sendable, Codable {
    public var maxStages: Int
    public var maxRetries: Int
    public var branchCount: Int
    public var webSearchEnabled: Bool
    public var maxSearchResults: Int
    public var webSearchContextBudget: Int
    public var maxSearchDepth: Int

    public init(
        maxStages: Int = 20,
        maxRetries: Int = 2,
        branchCount: Int = 3,
        webSearchEnabled: Bool = false,
        maxSearchResults: Int = 5,
        webSearchContextBudget: Int = 2000,
        maxSearchDepth: Int = 1
    ) {
        self.maxStages = maxStages
        self.maxRetries = maxRetries
        self.branchCount = branchCount
        self.webSearchEnabled = webSearchEnabled
        self.maxSearchResults = maxSearchResults
        self.webSearchContextBudget = webSearchContextBudget
        self.maxSearchDepth = maxSearchDepth
    }

    public static let `default` = PipelineConfiguration()
}

// MARK: - Pipeline Result

public struct PipelineResult: Sendable, Identifiable {
    public let id: String
    public let pipelineName: String
    public let query: String
    public let finalOutput: StageOutput
    public let stageOutputs: [StageOutput]
    public let trace: [TraceRecord]
    public let startTime: Date
    public let endTime: Date
    public let success: Bool

    public var totalDuration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    public init(
        id: String = UUID().uuidString,
        pipelineName: String,
        query: String,
        finalOutput: StageOutput,
        stageOutputs: [StageOutput],
        trace: [TraceRecord],
        startTime: Date,
        endTime: Date,
        success: Bool = true
    ) {
        self.id = id
        self.pipelineName = pipelineName
        self.query = query
        self.finalOutput = finalOutput
        self.stageOutputs = stageOutputs
        self.trace = trace
        self.startTime = startTime
        self.endTime = endTime
        self.success = success
    }
}

// MARK: - Pipeline Protocol

public protocol Pipeline: Sendable {
    var name: String { get }
    var description: String { get }
    var configuration: PipelineConfiguration { get }
    var stages: [any Stage] { get }

    func execute(query: String, context: PipelineContext) async throws -> PipelineResult
}

// MARK: - Pipeline Kind

public enum PipelineKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case auto
    case direct
    case rethink
    case verified

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: "Auto"
        case .direct: "Direct"
        case .rethink: "Rethink"
        case .verified: "Verified (CSP)"
        }
    }

    public var systemDescription: String {
        switch self {
        case .auto:
            "Automatically selects Direct, Rethink, or Verified"
        case .direct:
            "Single-pass answer (fast)"
        case .rethink:
            "Analyze+Solve → Independent Verify (accurate)"
        case .verified:
            "Extract Constraints → Deterministic Solve → Explain"
        }
    }

    public var isMultiPass: Bool {
        self != .direct
    }
}
