import Foundation
import FoundationModels

// MARK: - Foundation Model Provider

@available(iOS 26.0, macOS 26.0, *)
public final class FoundationModelProvider: ModelProvider, Sendable {

    public init() {}

    private func makeSession(instructions: String?) -> LanguageModelSession {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        if let instructions, !instructions.isEmpty {
            return LanguageModelSession(model: model, instructions: instructions)
        }
        return LanguageModelSession(model: model)
    }

    public func generate(systemPrompt: String?, userPrompt: String) async throws -> String {
        guard SystemLanguageModel.default.isAvailable else {
            throw StageError.modelUnavailable
        }

        let session = makeSession(instructions: systemPrompt)
        do {
            let response = try await session.respond(to: userPrompt)
            return response.content
        } catch {
            if Self.isSafetyFilterError(error) {
                throw ModelError.safetyFilterViolation
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

                let session = self.makeSession(instructions: systemPrompt)

                do {
                    let stream = session.streamResponse(to: userPrompt)
                    for try await partial in stream {
                        continuation.yield(partial.content)
                    }
                    continuation.finish()
                } catch {
                    if Self.isSafetyFilterError(error) {
                        continuation.finish(throwing: ModelError.safetyFilterViolation)
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
}
