import Foundation

// MARK: - Pipeline Configuration

public struct PipelineConfiguration: Sendable, Codable {
    public var maxStages: Int
    public var maxCritiqueReviseLoops: Int
    public var maxRetries: Int
    public var convergenceThreshold: Double
    public var confidenceThreshold: Double
    public var branchCount: Int
    public var webSearchEnabled: Bool
    public var maxSearchResults: Int

    public init(
        maxStages: Int = 20,
        maxCritiqueReviseLoops: Int = 3,
        maxRetries: Int = 2,
        convergenceThreshold: Double = 0.1,
        confidenceThreshold: Double = 0.7,
        branchCount: Int = 3,
        webSearchEnabled: Bool = false,
        maxSearchResults: Int = 5
    ) {
        self.maxStages = maxStages
        self.maxCritiqueReviseLoops = maxCritiqueReviseLoops
        self.maxRetries = maxRetries
        self.convergenceThreshold = convergenceThreshold
        self.confidenceThreshold = confidenceThreshold
        self.branchCount = branchCount
        self.webSearchEnabled = webSearchEnabled
        self.maxSearchResults = maxSearchResults
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
    case direct
    case sequential
    case critiqueLoop
    case branchMerge
    case selfConsistency
    case verified

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .direct: "Direct (Single-Pass)"
        case .sequential: "Sequential"
        case .critiqueLoop: "Critique Loop"
        case .branchMerge: "Branch & Merge"
        case .selfConsistency: "Self-Consistency"
        case .verified: "Verified (CSP)"
        }
    }

    public var systemDescription: String {
        switch self {
        case .direct:
            "Query -> Response (no reasoning stages)"
        case .sequential:
            "Analyze -> Plan -> Solve -> Finalize"
        case .critiqueLoop:
            "Analyze -> Solve -> Critique -> Revise -> Finalize"
        case .branchMerge:
            "Analyze -> {Solve A, B, C} -> Merge -> Finalize"
        case .selfConsistency:
            "Analyze -> Multi-Solve -> Aggregate -> Finalize"
        case .verified:
            "Extract Constraints -> Solve (deterministic) -> Explain"
        }
    }

    public var isMultiPass: Bool {
        self != .direct
    }
}
