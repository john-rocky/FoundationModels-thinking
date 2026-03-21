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

        let systemPrompt = "分析結果をもとに回答方針を立ててください。方針・必要観点・手順を簡潔に箇条書き。確信度(0.0-1.0)も。"

        let userPrompt = """
        質問: \(truncate(input.query, to: 300))

        分析: \(analysis)
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
