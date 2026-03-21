import Foundation

// MARK: - Plan Stage

public struct PlanStage: Stage {
    public let kind: StageKind = .plan
    public let name = "Plan"
    public let purpose = "最終回答へ至る方針、必要観点、処理順を整理する"

    public init() {}

    public func execute(input: StageInput, context: PipelineContext) async throws -> StageOutput {
        await context.traceCollector.record(
            event: .stageStarted(stage: name, kind: kind, input: input.query)
        )

        let analysisContext = input.previousOutputs["Analyze"]?.content ?? ""
        let memoryContext = formatMemoryContext(input.memoryContext)

        let systemPrompt = """
        あなたは計画立案の専門家です。分析結果をもとに、最終回答を導くための方針を立ててください。
        出力は以下の形式で返してください:

        ## 方針
        (全体方針を1-2文で)

        ## 必要な観点
        - (箇条書き)

        ## 処理順序
        1. (ステップ1)
        2. (ステップ2)
        ...

        ## リスク・注意点
        - (箇条書き)

        ## 確信度
        (0.0〜1.0の数値)
        """

        let userPrompt = """
        以下の分析結果をもとに計画を立ててください:

        【元の質問】
        \(input.query)

        【分析結果】
        \(analysisContext)
        \(memoryContext)
        """

        let raw = try await context.modelProvider.generate(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )

        let output = parseOutput(raw: raw, kind: .plan)

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
        await context.workingMemory.store(output: output, for: name)

        return output
    }
}
