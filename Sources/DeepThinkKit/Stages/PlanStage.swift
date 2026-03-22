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

        let analysis = input.previousOutputs["Analyze"].map { summarizeForNextStage($0) } ?? ""

        let systemPrompt = "あなたは回答設計者です。分析結果を踏まえ、最良の回答を組み立てるための具体的な手順を箇条書きで設計してください。各手順は「何を、どう述べるか」を明示すること。回答本文は書かないこと。確信度(0.0-1.0)も末尾に。"

        let userPrompt = """
        質問: \(truncate(input.query, to: 400))

        【分析結果】
        \(analysis)
        """

        let raw = try await streamingGenerate(
            stageName: name,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            context: context
        )

        let output = parseOutput(raw: raw, kind: .plan)

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
        await context.workingMemory.store(output: output, for: name)

        return output
    }
}
