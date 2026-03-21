import Foundation

// MARK: - Finalize Stage

public struct FinalizeStage: Stage {
    public let kind: StageKind = .finalize
    public let name = "Finalize"
    public let purpose = "最終出力を利用者向けに簡潔かつ安定的な形式へ整える"

    public init() {}

    public func execute(input: StageInput, context: PipelineContext) async throws -> StageOutput {
        await context.traceCollector.record(
            event: .stageStarted(stage: name, kind: kind, input: input.query)
        )

        let bestAnswer = findBestAnswer(from: input.previousOutputs)

        let systemPrompt = """
        あなたは編集・仕上げの専門家です。
        これまでの処理結果を、利用者が読みやすい最終回答に整えてください。
        余分な内部メモやメタ情報は除き、簡潔で明確な回答にしてください。

        出力形式:
        ## 回答
        (最終回答の本文)

        ## 要点まとめ
        - (重要ポイントを箇条書き)

        ## 確信度
        (0.0〜1.0の数値)
        """

        let userPrompt = """
        以下の処理結果を最終回答に整えてください:

        【元の質問】
        \(input.query)

        【処理結果】
        \(bestAnswer)
        """

        let raw = try await context.modelProvider.generate(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )

        let output = parseOutput(raw: raw, kind: .finalize)

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))

        return output
    }

    private func findBestAnswer(from outputs: [String: StageOutput]) -> String {
        if let revised = outputs.first(where: { $0.value.stageKind == .revise })?.value {
            return revised.content
        }
        if let solved = outputs.first(where: { $0.value.stageKind == .solve })?.value {
            return solved.content
        }
        if let merged = outputs.first(where: { $0.value.stageKind == .merge })?.value {
            return merged.content
        }
        if let aggregated = outputs.first(where: { $0.value.stageKind == .aggregate })?.value {
            return aggregated.content
        }
        return outputs.values
            .sorted { $0.timestamp > $1.timestamp }
            .first?.content ?? ""
    }
}
