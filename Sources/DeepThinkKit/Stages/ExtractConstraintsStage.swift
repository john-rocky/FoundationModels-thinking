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
        if context.language.isJapanese {
            systemPrompt = """
            問題文から制約を抽出し、以下のJSON形式で出力してください。JSON以外は出力しないこと。

            {"variables":["A","B","C"],"domain":["1","2","3"],"constraints":[{"type":"equal","args":["B","2"]},{"type":"notAdjacent","args":["A","B"]},{"type":"greaterThan","args":["C","A"]},{"type":"atBoundary","args":["A"]}]}

            type: equal(変数=値), notEqual(変数≠値), notAdjacent(隣接不可), lessThan(左), greaterThan(右), atBoundary(端)
            domain: 位置番号を文字列で(例:["1","2","3","4","5"])
            """
        } else {
            systemPrompt = """
            Extract constraints from the problem and output ONLY JSON in this format:

            {"variables":["A","B","C"],"domain":["1","2","3"],"constraints":[{"type":"equal","args":["B","2"]},{"type":"notAdjacent","args":["A","B"]},{"type":"greaterThan","args":["C","A"]},{"type":"atBoundary","args":["A"]}]}

            type: equal(var=val), notEqual(var≠val), notAdjacent(not next to), lessThan(left of), greaterThan(right of), atBoundary(at end)
            domain: position numbers as strings (e.g. ["1","2","3","4","5"])
            """
        }

        let raw = try await streamingGenerate(
            stageName: name,
            systemPrompt: systemPrompt,
            userPrompt: truncate(input.query, to: 800),
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
