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

        let systemPrompt = "入力を分析し、主要トピック・制約・不明点を箇条書きで整理してください。最後に確信度(0.0-1.0)を書いてください。簡潔に。"

        let userPrompt = truncate(input.query, to: 800)

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
