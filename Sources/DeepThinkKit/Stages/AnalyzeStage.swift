import Foundation

// MARK: - Analyze Stage

public struct AnalyzeStage: Stage {
    public let kind: StageKind = .analyze
    public let name = "Analyze"
    public let purpose = "入力を分解し、主要トピック・制約・未確定点・候補タスクを抽出する"

    public init() {}

    public func execute(input: StageInput, context: PipelineContext) async throws -> StageOutput {
        await context.traceCollector.record(
            event: .stageStarted(stage: name, kind: kind, input: input.query)
        )

        let systemPrompt = "あなたは問題分析の専門家です。質問を分解し、以下を箇条書きで出力してください：(1)核心的な問い (2)必要な知識領域 (3)隠れた前提や制約 (4)曖昧な点。回答は書かないこと。確信度(0.0-1.0)も末尾に。"

        let userPrompt = truncate(input.query, to: 1000)

        let raw = try await streamingGenerate(
            stageName: name,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            context: context
        )

        let output = parseOutput(raw: raw, kind: .analyze)

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
        await context.workingMemory.store(output: output, for: name)

        return output
    }
}
