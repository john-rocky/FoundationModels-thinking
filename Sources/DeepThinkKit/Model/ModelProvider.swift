import Foundation

// MARK: - Model Provider Protocol

public protocol ModelProvider: Sendable {
    func generate(systemPrompt: String?, userPrompt: String) async throws -> String
}

// MARK: - Model Error

public enum ModelError: Error, Sendable {
    case modelUnavailable
    case generationFailed(String)
    case contextTooLong
    case rateLimited
    case safetyFilterViolation
}
