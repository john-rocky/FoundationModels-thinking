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
        })?.value.content ?? ""

        let systemPrompt = """
        あなたは批評の専門家です。与えられた回答を厳しく評価してください。
        以下の観点で批評してください:

        ## 弱点
        - (箇条書き)

        ## 曖昧な箇所
        - (箇条書き)

        ## 矛盾点
        - (箇条書き、あれば)

        ## 根拠不足
        - (箇条書き、あれば)

        ## 改善提案
        - (箇条書き)

        ## 総合評価
        (改善の必要度を0.0〜1.0で。0.0=修正不要、1.0=全面修正)

        ## 確信度
        (この批評の確信度を0.0〜1.0で)
        """

        let userPrompt = """
        以下の回答を批評してください:

        【元の質問】
        \(input.query)

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
