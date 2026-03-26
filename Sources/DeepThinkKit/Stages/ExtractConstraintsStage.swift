import Foundation
import FoundationModels

// MARK: - Extract Constraints Stage (LLM with @Generable)

@available(iOS 26.0, macOS 26.0, *)
public struct ExtractConstraintsStage: Stage {
    public let kind: StageKind = .analyze
    public let name = "Extract"
    public let purpose = "Extract structured constraints from natural language problem"

    public init() {}

    public func execute(input: StageInput, context: PipelineContext) async throws -> StageOutput {
        await context.traceCollector.record(
            event: .stageStarted(stage: name, kind: kind, input: input.query)
        )

        guard SystemLanguageModel.default.isAvailable else {
            throw StageError.modelUnavailable
        }

        let instructions = localizedSystemPrompt(
            "Extract constraints from the problem. Use variable names, position domain, and constraint types: equal, notEqual, notAdjacent, lessThan, greaterThan, atBoundary.",
            language: context.language
        )

        let session = LanguageModelSession(instructions: instructions)

        do {
            let response = try await session.respond(
                to: truncate(input.query, to: 500),
                generating: CSPProblem.self
            )

            let problem = response.content
            await context.emit(.stageStreamingContent(stageName: name, content: "Extracted \(problem.variables.count) variables, \(problem.constraints.count) constraints"))

            var metadata: [String: String] = ["csp_valid": "true"]
            if let json = try? JSONEncoder().encode(problem) {
                metadata["csp_json"] = String(data: json, encoding: .utf8) ?? ""
            }

            let summary = "Variables: \(problem.variables.joined(separator: ", "))\nDomain: \(problem.domain.joined(separator: ", "))\nConstraints: \(problem.constraints.count)"

            let output = StageOutput(
                stageKind: .analyze,
                content: summary,
                confidence: 0.9,
                metadata: metadata
            )

            await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
            return output

        } catch {
            // Fallback: mark as failed so Explain stage does direct LLM answer
            let output = StageOutput(
                stageKind: .analyze,
                content: "Constraint extraction failed: \(error.localizedDescription)",
                confidence: 0.1,
                metadata: ["csp_valid": "false"]
            )
            await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
            return output
        }
    }
}
