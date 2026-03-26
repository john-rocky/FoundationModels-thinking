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

        let session: LanguageModelSession
        if let systemPrompt, !systemPrompt.isEmpty {
            session = LanguageModelSession(instructions: systemPrompt)
        } else {
            session = LanguageModelSession()
        }

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

                let session: LanguageModelSession
                if let systemPrompt, !systemPrompt.isEmpty {
                    session = LanguageModelSession(instructions: systemPrompt)
                } else {
                    session = LanguageModelSession()
                }

                do {
                    let stream = session.streamResponse(to: userPrompt)
                    for try await partial in stream {
                        continuation.yield(partial.content)
                    }
                    continuation.finish()
                } catch {
                    Self.finishWithError(error, continuation: continuation)
                }
            }
        }
    }

    /// Sanitize instructions to reduce safety guard triggers by replacing aggressive language
    static func sanitizeInstructions(_ instructions: String) -> String {
        var result = instructions
        let replacements: [(String, String)] = [
            ("ASSUME the answer below is WRONG", "Carefully evaluate whether the answer below is correct"),
            ("ASSUME the answer is WRONG", "Carefully evaluate whether the answer is correct"),
            ("間違っていると仮定", "正しいかどうか慎重に検証"),
            ("反証する反例を見つけよ", "反例がないか検討してください"),
        ]
        for (pattern, replacement) in replacements {
            result = result.replacingOccurrences(of: pattern, with: replacement)
        }
        return result
    }

    /// Finish a stream continuation with a classified error
    static func finishWithError(_ error: Error, continuation: AsyncThrowingStream<String, Error>.Continuation) {
        if isSafetyFilterError(error) {
            continuation.finish(throwing: ModelError.safetyFilterViolation)
        } else if isContextTooLongError(error) {
            continuation.finish(throwing: ModelError.contextTooLong)
        } else {
            continuation.finish(throwing: error)
        }
    }

    static func buildPrompt(systemPrompt: String?, userPrompt: String) -> String {
        if let systemPrompt, !systemPrompt.isEmpty {
            return "[Instructions]\n\(systemPrompt)\n\n[Query]\n\(userPrompt)"
        }
        return userPrompt
    }

    static func isSafetyFilterError(_ error: Error) -> Bool {
        let desc = String(describing: error)
        if desc.contains("guardrail") || desc.contains("unsafe") {
            return true
        }
        let localized = error.localizedDescription
        return localized.contains("unsafe") || localized.contains("guardrail")
    }

    static func isContextTooLongError(_ error: Error) -> Bool {
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

// MARK: - Multi-Turn Session Protocols

/// A multi-turn session that preserves conversation history across calls.
public protocol ModelSession: Sendable {
    func streamResponse(to prompt: String) async throws -> AsyncThrowingStream<String, Error>
}

/// Provider that can create multi-turn sessions.
public protocol ModelSessionProvider: Sendable {
    func createSession(instructions: String?) -> any ModelSession
}

// MARK: - Foundation Model Session (Multi-Turn)

@available(iOS 26.0, macOS 26.0, *)
extension FoundationModelProvider: ModelSessionProvider {
    public func createSession(instructions: String?) -> any ModelSession {
        FoundationModelSession(instructions: instructions)
    }
}

@available(iOS 26.0, macOS 26.0, *)
final class FoundationModelSession: ModelSession, @unchecked Sendable {
    private let instructions: String?
    private var session: LanguageModelSession?
    private var usedFallback = false

    init(instructions: String?) {
        self.instructions = instructions
    }

    func streamResponse(to prompt: String) async throws -> AsyncThrowingStream<String, Error> {
        guard SystemLanguageModel.default.isAvailable else {
            throw StageError.modelUnavailable
        }

        // Lazy session creation on first call
        if session == nil {
            if let instructions, !instructions.isEmpty {
                let sanitized = FoundationModelProvider.sanitizeInstructions(instructions)
                session = LanguageModelSession(instructions: sanitized)
            } else {
                session = LanguageModelSession()
            }
        }

        let currentSession = session!

        return AsyncThrowingStream { continuation in
            Task { [weak self] in
                var yieldedContent = false
                do {
                    let stream = currentSession.streamResponse(to: prompt)
                    for try await partial in stream {
                        yieldedContent = true
                        continuation.yield(partial.content)
                    }
                    continuation.finish()
                } catch {
                    if FoundationModelProvider.isSafetyFilterError(error) && !yieldedContent,
                       let self, !self.usedFallback {
                        // Fallback: recreate session without instructions, embed in prompt
                        self.usedFallback = true
                        self.session = LanguageModelSession()
                        let fallbackPrompt = FoundationModelProvider.buildPrompt(
                            systemPrompt: self.instructions, userPrompt: prompt
                        )
                        do {
                            let fallbackStream = self.session!.streamResponse(to: fallbackPrompt)
                            for try await partial in fallbackStream {
                                continuation.yield(partial.content)
                            }
                            continuation.finish()
                        } catch {
                            FoundationModelProvider.finishWithError(error, continuation: continuation)
                        }
                    } else if FoundationModelProvider.isContextTooLongError(error) {
                        continuation.finish(throwing: ModelError.contextTooLong)
                    } else {
                        FoundationModelProvider.finishWithError(error, continuation: continuation)
                    }
                }
            }
        }
    }
}
