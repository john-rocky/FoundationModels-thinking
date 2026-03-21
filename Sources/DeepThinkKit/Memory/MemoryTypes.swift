import Foundation

// MARK: - Memory Entry Kind

public enum MemoryKind: String, Codable, Sendable, CaseIterable {
    case fact
    case decision
    case constraint
    case summary
    case critique
    case intermediate
    case artifact
    case question
}

// MARK: - Memory Entry

public struct MemoryEntry: Sendable, Codable, Identifiable {
    public let id: String
    public let kind: MemoryKind
    public let content: String
    public let tags: [String]
    public let source: String
    public let priority: MemoryPriority
    public let createdAt: Date
    public let sessionId: String?
    public var metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        kind: MemoryKind,
        content: String,
        tags: [String] = [],
        source: String = "",
        priority: MemoryPriority = .normal,
        createdAt: Date = .now,
        sessionId: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.content = content
        self.tags = tags
        self.source = source
        self.priority = priority
        self.createdAt = createdAt
        self.sessionId = sessionId
        self.metadata = metadata
    }
}

// MARK: - Memory Priority

public enum MemoryPriority: Int, Codable, Sendable, Comparable {
    case low = 0
    case normal = 1
    case high = 2
    case pinned = 3

    public static func < (lhs: MemoryPriority, rhs: MemoryPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Memory Search Query

public struct MemorySearchQuery: Sendable {
    public let text: String?
    public let kinds: [MemoryKind]?
    public let tags: [String]?
    public let limit: Int
    public let minPriority: MemoryPriority?

    public init(
        text: String? = nil,
        kinds: [MemoryKind]? = nil,
        tags: [String]? = nil,
        limit: Int = 5,
        minPriority: MemoryPriority? = nil
    ) {
        self.text = text
        self.kinds = kinds
        self.tags = tags
        self.limit = limit
        self.minPriority = minPriority
    }
}

// MARK: - Memory Layer

public enum MemoryLayer: String, Sendable, Codable {
    case session
    case working
    case longTerm
}
