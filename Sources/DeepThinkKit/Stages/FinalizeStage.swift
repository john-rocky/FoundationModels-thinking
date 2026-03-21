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

        let systemPrompt = "処理結果を利用者向けの読みやすい最終回答に整えてください。内部メモや確信度は除き、自然な文章で。"

        let userPrompt = """
        質問: \(truncate(input.query, to: 200))

        処理結果: \(truncate(bestAnswer, to: 600))
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
