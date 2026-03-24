import Foundation

// MARK: - Model Provider Protocol

public protocol ModelProvider: Sendable {
    func generate(systemPrompt: String?, userPrompt: String) async throws -> String
    func generateStream(systemPrompt: String?, userPrompt: String) -> AsyncThrowingStream<String, Error>
}

extension ModelProvider {
    public func generateStream(systemPrompt: String?, userPrompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let result = try await self.generate(systemPrompt: systemPrompt, userPrompt: userPrompt)
                    continuation.yield(result)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - Model Error

public enum ModelError: Error, Sendable {
    case modelUnavailable
    case generationFailed(String)
    case contextTooLong
    case rateLimited
    case safetyFilterViolation

    public var isSafetyFilter: Bool {
        if case .safetyFilterViolation = self { return true }
        return false
    }
}
