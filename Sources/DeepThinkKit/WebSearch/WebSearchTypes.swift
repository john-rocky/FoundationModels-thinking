import Foundation

// MARK: - Search Decision

public struct SearchDecision: Sendable {
    public let shouldSearch: Bool
    public let reason: String
    public let keywords: String

    public init(shouldSearch: Bool, reason: String, keywords: String) {
        self.shouldSearch = shouldSearch
        self.reason = reason
        self.keywords = keywords
    }
}
