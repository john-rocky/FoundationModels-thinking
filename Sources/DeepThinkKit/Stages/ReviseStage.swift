import Foundation

// MARK: - Revise Stage

public struct ReviseStage: Stage {
    public let kind: StageKind = .revise
    public let name = "Revise"
    public let purpose = "critique 結果をもとに回答を修正する"

    public init() {}

    public func execute(input: StageInput, context: PipelineContext) async throws -> StageOutput {
        await context.traceCollector.record(
            event: .stageStarted(stage: name, kind: kind, input: input.query)
        )

        let solveContent = input.previousOutputs.first(where: {
            $0.value.stageKind == .solve || $0.value.stageKind == .revise
        })?.value.content ?? ""

        let critiqueContent = input.previousOutputs["Critique"]?.content ?? ""

        let systemPrompt = """
        あなたは回答改善の専門家です。批評をもとに回答を修正・改善してください。
        修正後の回答を以下の形式で返してください:

        ## 修正回答
        (修正された本文)

        ## 修正箇所
        - (何をどう修正したか、箇条書き)

        ## 残存課題
        - (まだ改善の余地がある点、箇条書き)

        ## 確信度
        (0.0〜1.0の数値)
        """

        let userPrompt = """
        以下の批評をもとに回答を修正してください:

        【元の質問】
        \(input.query)

        【現在の回答】
        \(solveContent)

        【批評】
        \(critiqueContent)
        """

        let raw = try await context.modelProvider.generate(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )

        let output = parseOutput(raw: raw, kind: .revise)

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
        await context.workingMemory.store(output: output, for: name)

        return output
    }
}
