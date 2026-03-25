import Foundation

// MARK: - Extract Constraints Stage (LLM)

public struct ExtractConstraintsStage: Stage {
    public let kind: StageKind = .analyze
    public let name = "Extract"
    public let purpose = "Extract structured constraints from natural language problem"

    public init() {}

    public func execute(input: StageInput, context: PipelineContext) async throws -> StageOutput {
        await context.traceCollector.record(
            event: .stageStarted(stage: name, kind: kind, input: input.query)
        )

        let systemPrompt: String
        let schema = """
        {"variables":["A","B","C"],"domain":["1","2","3"],"constraints":[{"type":"equal","args":["B","2"]},{"type":"notAdjacent","args":["A","C"]},{"type":"greaterThan","args":["C","A"]},{"type":"atBoundary","args":["A"]}]}
        """

        if context.language.isJapanese {
            systemPrompt = "JSONのみ出力。説明不要。形式:\n\(schema)\ntype: equal(=), notEqual(≠), notAdjacent(隣接不可), lessThan(<), greaterThan(>), atBoundary(端)"
        } else {
            systemPrompt = "Output ONLY JSON. No explanation. Format:\n\(schema)\ntype: equal(=), notEqual(≠), notAdjacent(not next to), lessThan(<), greaterThan(>), atBoundary(at end)"
        }

        let userPrompt = "Convert to JSON:\n\(truncate(input.query, to: 600))"

        let raw = try await streamingGenerate(
            stageName: name,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            context: context
        )

        let parsed = Self.parseCSP(from: raw)
        var metadata: [String: String] = [:]
        if let problem = parsed, let json = try? JSONEncoder().encode(problem) {
            metadata["csp_json"] = String(data: json, encoding: .utf8) ?? ""
            metadata["csp_valid"] = "true"
        } else {
            metadata["csp_valid"] = "false"
        }

        let output = StageOutput(
            stageKind: .analyze,
            content: raw,
            confidence: parsed != nil ? 0.8 : 0.2,
            metadata: metadata
        )

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
        return output
    }

    static func parseCSP(from text: String) -> CSPProblem? {
        // Find JSON object in the text
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else { return nil }
        let jsonString = String(text[start...end])
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CSPProblem.self, from: data)
    }
}
