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

        // Try rate/chase problem extraction first (simpler for the model)
        if let output = await tryRateExtraction(input: input, context: context) {
            return output
        }

        // Fall back to CSP constraint extraction
        return await extractCSP(input: input, context: context)
    }

    // MARK: - Rate Problem Extraction

    private func tryRateExtraction(input: StageInput, context: PipelineContext) async -> StageOutput? {
        let query = input.query.lowercased()
        let rateKeywords = [
            "km/h", "mph", "m/s", "catch up", "catches up", "overtake", "chase",
            "時速", "分速", "秒速", "追いつ", "追いかけ",
        ]
        guard rateKeywords.contains(where: { query.contains($0) }) else { return nil }

        let instructions = localizedSystemPrompt(
            "Extract the two speeds and time delay from this pursuit problem.",
            language: context.language
        )
        let session = LanguageModelSession(instructions: instructions)

        do {
            let response = try await session.respond(
                to: truncate(input.query, to: 500),
                generating: RateProblem.self
            )
            let problem = response.content
            await context.emit(.stageStreamingContent(
                stageName: name, content: "Extracted rate problem: slow=\(problem.speedSlow), fast=\(problem.speedFast), delay=\(problem.delay)"
            ))

            var metadata: [String: String] = ["rate_valid": "true"]
            if let json = try? JSONEncoder().encode(problem) {
                metadata["rate_json"] = String(data: json, encoding: .utf8) ?? ""
            }

            let summary = "Rate problem: slow=\(problem.speedSlow), fast=\(problem.speedFast), delay=\(problem.delay)"
            let output = StageOutput(
                stageKind: .analyze,
                content: summary,
                confidence: 0.9,
                metadata: metadata
            )
            await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
            return output
        } catch {
            return nil // Fall through to CSP extraction
        }
    }

    // MARK: - CSP Extraction

    private func extractCSP(input: StageInput, context: PipelineContext) async -> StageOutput {
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
