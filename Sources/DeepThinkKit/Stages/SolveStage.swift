import Foundation

// MARK: - Solve Stage

public struct SolveStage: Stage {
    public let kind: StageKind = .solve
    public let name: String
    public let purpose = "plan や analyze 結果をもとに主回答を生成する"

    public init(name: String = "Solve") {
        self.name = name
    }

    public func execute(input: StageInput, context: PipelineContext) async throws -> StageOutput {
        await context.traceCollector.record(
            event: .stageStarted(stage: name, kind: kind, input: input.query)
        )

        let analyzeContent = input.previousOutputs["Analyze"]?.content ?? ""
        let planContent = input.previousOutputs["Plan"]?.content ?? ""
        let memoryContext = formatMemoryContext(input.memoryContext)

        let systemPrompt = """
        あなたは問題解決の専門家です。分析と計画をもとに、質問に対する回答を生成してください。
        回答は以下の形式で返してください:

        ## 回答
        (本文)

        ## 要点
        - (箇条書き)

        ## 前提条件
        - (箇条書き、あれば)

        ## 未解決事項
        - (箇条書き、あれば)

        ## 確信度
        (0.0〜1.0の数値)
        """

        let userPrompt = """
        以下の情報をもとに回答を生成してください:

        【元の質問】
        \(input.query)

        【分析結果】
        \(analyzeContent)

        【計画】
        \(planContent)
        \(memoryContext)
        """

        let raw = try await context.modelProvider.generate(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )

        let output = parseOutput(raw: raw, kind: .solve)

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
        await context.workingMemory.store(output: output, for: name)

        return output
    }
}
