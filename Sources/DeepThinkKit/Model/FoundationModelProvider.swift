import Foundation
import FoundationModels

// MARK: - Foundation Model Provider

@available(iOS 26.0, macOS 26.0, *)
public final class FoundationModelProvider: ModelProvider, Sendable {

    public init() {}

    public func generate(systemPrompt: String?, userPrompt: String) async throws -> String {
        guard SystemLanguageModel.default.isAvailable else {
            throw StageError.modelUnavailable
        }

        let session = Self.makeSession(systemPrompt: systemPrompt)
        do {
            let response = try await session.respond(to: userPrompt)
            return response.content
        } catch {
            throw Self.mapError(error)
        }
    }

    public func generateStream(systemPrompt: String?, userPrompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                guard SystemLanguageModel.default.isAvailable else {
                    continuation.finish(throwing: StageError.modelUnavailable)
                    return
                }

                let session = Self.makeSession(systemPrompt: systemPrompt)
                do {
                    for try await partial in session.streamResponse(to: userPrompt) {
                        if Task.isCancelled { break }
                        continuation.yield(partial.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.mapError(error))
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func makeSession(systemPrompt: String?) -> LanguageModelSession {
        if let systemPrompt, !systemPrompt.isEmpty {
            return LanguageModelSession(instructions: systemPrompt)
        }
        return LanguageModelSession()
    }

    private static func mapError(_ error: Error) -> Error {
        if isSafetyFilterError(error) {
            return ModelError.safetyFilterViolation
        }
        if isContextTooLongError(error) {
            return ModelError.contextTooLong
        }
        return error
    }

    private static func isSafetyFilterError(_ error: Error) -> Bool {
        let desc = String(describing: error)
        if desc.contains("guardrail") || desc.contains("unsafe") {
            return true
        }
        let localized = error.localizedDescription
        return localized.contains("unsafe") || localized.contains("guardrail")
    }

    private static func isContextTooLongError(_ error: Error) -> Bool {
        let desc = String(describing: error)
        let localized = error.localizedDescription
        let combined = desc + " " + localized
        return combined.contains("too long")
            || combined.contains("too many tokens")
            || combined.contains("context length")
            || combined.contains("maximum")
            || combined.contains("exceeds")
            || combined.contains("token limit")
    }
}
