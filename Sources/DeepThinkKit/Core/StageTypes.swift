import Foundation

// MARK: - Stage Kind

public enum StageKind: String, Codable, Sendable, CaseIterable {
    case analyze
    case solve
    case finalize
    case webSearch
    case think
    case critique
    // Legacy cases kept for Codable compatibility
    case plan
    case revise
    case retrieveMemory
    case summarizeMemory
    case merge
    case aggregate
    case custom
}

// MARK: - Stage Input

public struct StageInput: Sendable {
    public let query: String
    public let previousOutputs: [String: StageOutput]
    public let memoryContext: [MemoryEntry]
    public let metadata: [String: String]

    public init(
        query: String,
        previousOutputs: [String: StageOutput] = [:],
        memoryContext: [MemoryEntry] = [],
        metadata: [String: String] = [:]
    ) {
        self.query = query
        self.previousOutputs = previousOutputs
        self.memoryContext = memoryContext
        self.metadata = metadata
    }
}

// MARK: - Stage Output

public struct StageOutput: Sendable, Codable, Identifiable {
    public let id: String
    public let stageKind: StageKind
    public let content: String
    public let bulletPoints: [String]
    public let confidence: Double
    public let unresolvedIssues: [String]
    public let assumptions: [String]
    public let nextAction: String?
    public let metadata: [String: String]
    public let timestamp: Date

    public init(
        id: String = UUID().uuidString,
        stageKind: StageKind,
        content: String,
        bulletPoints: [String] = [],
        confidence: Double = 0.5,
        unresolvedIssues: [String] = [],
        assumptions: [String] = [],
        nextAction: String? = nil,
        metadata: [String: String] = [:],
        timestamp: Date = .now
    ) {
        self.id = id
        self.stageKind = stageKind
        self.content = content
        self.bulletPoints = bulletPoints
        self.confidence = confidence
        self.unresolvedIssues = unresolvedIssues
        self.assumptions = assumptions
        self.nextAction = nextAction
        self.metadata = metadata
        self.timestamp = timestamp
    }
}

// MARK: - Stage Error

public enum StageError: Error, Sendable, LocalizedError {
    case generationFailed(stage: String, underlying: Error)
    case parseFailed(stage: String, rawOutput: String)
    case missingInput(stage: String, required: String)
    case maxRetriesExceeded(stage: String, attempts: Int, lastError: Error?)
    case convergenceFailed(stage: String, iterations: Int)
    case memoryRetrievalFailed(underlying: Error)
    case pipelineAborted(reason: String)
    case contentFiltered(stage: String)
    case contextTooLong(stage: String)
    case modelUnavailable

    public var errorDescription: String? {
        switch self {
        case .generationFailed(let stage, let err):
            "[\(stage)] Generation failed: \(err.localizedDescription)"
        case .parseFailed(let stage, _):
            "[\(stage)] Failed to parse model output"
        case .missingInput(let stage, let required):
            "[\(stage)] Missing required input: \(required)"
        case .maxRetriesExceeded(let stage, let attempts, let lastError):
            "[\(stage)] Failed after \(attempts) attempts. Last error: \(lastError?.localizedDescription ?? "unknown")"
        case .convergenceFailed(let stage, let iterations):
            "[\(stage)] Did not converge after \(iterations) iterations"
        case .memoryRetrievalFailed(let err):
            "Memory retrieval failed: \(err.localizedDescription)"
        case .contentFiltered(let stage):
            "[\(stage)] This input was blocked by Apple Intelligence's safety filter. Try rephrasing your input or using more specific wording."
        case .contextTooLong(let stage):
            "[\(stage)] Input too long to process. Try a shorter or more focused question."
        case .pipelineAborted(let reason):
            "Pipeline aborted: \(reason)"
        case .modelUnavailable:
            "Apple Intelligence model is not available on this device. Ensure you have an Apple Silicon Mac or supported iPhone/iPad, and that Apple Intelligence is enabled in Settings."
        }
    }
}
