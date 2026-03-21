import Foundation

// MARK: - Critique Stage

public struct CritiqueStage: Stage {
    public let kind: StageKind = .critique
    public let name = "Critique"
    public let purpose = "主回答の弱点・曖昧さ・矛盾・根拠不足を抽出する"

    public init() {}

    public func execute(input: StageInput, context: PipelineContext) async throws -> StageOutput {
        await context.traceCollector.record(
            event: .stageStarted(stage: name, kind: kind, input: input.query)
        )

        let solveContent = input.previousOutputs.first(where: {
            $0.value.stageKind == .solve || $0.value.stageKind == .revise
        }).map { summarizeForNextStage($0.value) } ?? ""

        let systemPrompt = "あなたは厳格な査読者です。回答の以下の観点を検証し、具体的な問題を箇条書きで指摘してください：(1)事実の正確性 (2)論理の一貫性 (3)質問への網羅性 (4)説明の明確さ。問題がない観点は省略可。改善案も簡潔に。確信度(0.0-1.0)も末尾に。"

        let userPrompt = """
        質問: \(truncate(input.query, to: 300))

        【回答】
        \(solveContent)
        """

        let raw = try await context.modelProvider.generate(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )

        let output = parseOutput(raw: raw, kind: .critique)

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
        await context.workingMemory.store(output: output, for: name)

        return output
    }
}
