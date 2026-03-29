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

        // Try general word problem extraction first.
        // The @Generable extraction itself acts as the classifier:
        // if the model can fill the struct, it's a word problem with numerical values.
        // The solver then pattern-matches to decide if it can solve deterministically.
        if let output = await tryWordProblemExtraction(input: input, context: context) {
            return output
        }

        // Fall back to CSP constraint extraction
        return await extractCSP(input: input, context: context)
    }

    // MARK: - Word Problem Extraction (General)

    private func tryWordProblemExtraction(input: StageInput, context: PipelineContext) async -> StageOutput? {
        let instructions = localizedSystemPrompt(
            "Extract all numerical values from the problem. Tag each value with its role: speed, time, delay, distance, count, price, rate, age, or weight.",
            language: context.language
        )
        let session = LanguageModelSession(instructions: instructions)

        do {
            let response = try await session.respond(
                to: truncate(input.query, to: 500),
                generating: WordProblemExtraction.self
            )
            let extraction = response.content
            guard !extraction.values.isEmpty else { return nil }

            // Check if the equation solver recognizes a solvable pattern
            let solver = EquationSolver()
            guard solver.solve(extraction) != nil else { return nil }

            let summary = extraction.values.map { "\($0.role): \($0.value)" }.joined(separator: ", ")
            await context.emit(.stageStreamingContent(
                stageName: name, content: "Extracted: \(summary)"
            ))

            var metadata: [String: String] = ["eq_valid": "true"]
            if let json = try? JSONEncoder().encode(extraction) {
                metadata["eq_json"] = String(data: json, encoding: .utf8) ?? ""
            }

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
