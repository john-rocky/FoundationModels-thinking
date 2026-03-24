import Foundation

// MARK: - Critique Stage

public struct CritiqueStage: Stage {
    public let kind: StageKind = .critique
    public let name = "Critique"
    public let purpose = "Extract weaknesses, ambiguities, contradictions, and lack of evidence from the main answer"

    public init() {}

    public func execute(input: StageInput, context: PipelineContext) async throws -> StageOutput {
        await context.traceCollector.record(
            event: .stageStarted(stage: name, kind: kind, input: input.query)
        )

        let solveContent = input.previousOutputs.first(where: {
            $0.value.stageKind == .solve || $0.value.stageKind == .revise
        }).map { summarizeForNextStage($0.value) } ?? ""

        let systemPrompt: String
        let userPrompt: String

        if context.language.isJapanese {
            systemPrompt = "あなたは厳格な査読者です。回答の以下の観点を検証し、具体的な問題を箇条書きで指摘してください：(1)事実の正確性 (2)論理の一貫性 (3)質問への網羅性 (4)説明の明確さ。問題がない観点は省略可。改善案も簡潔に。確信度(0.0-1.0)も末尾に。"
            userPrompt = "質問: \(truncate(input.query, to: 300))\n\n【回答】\n\(solveContent)"
        } else {
            systemPrompt = "You are a strict reviewer. Verify the answer on these aspects and list specific issues as bullet points: (1) Factual accuracy (2) Logical consistency (3) Completeness (4) Clarity. Skip aspects with no issues. Include brief improvement suggestions. Confidence (0.0-1.0) at the end."
            userPrompt = "Question: \(truncate(input.query, to: 300))\n\n[Answer]\n\(solveContent)"
        }

        let raw = try await streamingGenerate(
            stageName: name,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            context: context
        )

        let output = parseOutput(raw: raw, kind: .critique)

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
        await context.workingMemory.store(output: output, for: name)

        return output
    }
}
