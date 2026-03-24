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

        let session = LanguageModelSession()
        do {
            let response = try await session.respond(to: userPrompt)
            return response.content
        } catch {
            if Self.isSafetyFilterError(error) {
                throw ModelError.safetyFilterViolation
            }
            if Self.isContextTooLongError(error) {
                throw ModelError.contextTooLong
            }
            throw error
        }
    }

    public func generateStream(systemPrompt: String?, userPrompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard SystemLanguageModel.default.isAvailable else {
                    continuation.finish(throwing: StageError.modelUnavailable)
                    return
                }

                let session = LanguageModelSession()

                do {
                    let stream = session.streamResponse(to: userPrompt)
                    for try await partial in stream {
                        continuation.yield(partial.content)
                    }
                    continuation.finish()
                } catch {
                    if Self.isSafetyFilterError(error) {
                        continuation.finish(throwing: ModelError.safetyFilterViolation)
                    } else if Self.isContextTooLongError(error) {
                        continuation.finish(throwing: ModelError.contextTooLong)
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
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
