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

        let memoryContext = formatMemoryContext(input.memoryContext)
        let systemPrompt = """
        あなたは分析の専門家です。与えられた入力を以下の観点で分解・整理してください。
        出力は以下の形式で返してください:

        ## 主要トピック
        - (箇条書きで列挙)

        ## 制約条件
        - (箇条書きで列挙)

        ## 未確定点・不明点
        - (箇条書きで列挙)

        ## 候補タスク
        - (箇条書きで列挙)

        ## 要約
        (1-3文の要約)

        ## 確信度
        (0.0〜1.0の数値)
        """

        let userPrompt = """
        以下の入力を分析してください:

        \(input.query)
        \(memoryContext)
        """

        let raw = try await context.modelProvider.generate(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )

        let output = parseOutput(raw: raw, kind: .analyze)

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
        await context.workingMemory.store(output: output, for: name)

        return output
    }
}
