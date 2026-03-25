import Foundation

// MARK: - Revise Stage

public struct ReviseStage: Stage {
    public let kind: StageKind = .revise
    public let name = "Revise"
    public let purpose = "Revise the answer based on critique results"

    public init() {}

    public func execute(input: StageInput, context: PipelineContext) async throws -> StageOutput {
        await context.traceCollector.record(
            event: .stageStarted(stage: name, kind: kind, input: input.query)
        )

        let solveContent = input.previousOutputs.first(where: {
            $0.value.stageKind == .solve || $0.value.stageKind == .revise
        }).map { summarizeForNextStage($0.value) } ?? ""

        let critiqueContent = input.previousOutputs["Critique"].map { summarizeForNextStage($0) } ?? ""

        let systemPrompt: String
        let userPrompt: String

        if context.language.isJapanese {
            systemPrompt = "批評の指摘を修正し、改善した完全な回答を出力してください。"
            userPrompt = "質問: \(truncate(input.query, to: 300))\n\n【現在の回答】\n\(solveContent)\n\n【批評・改善指示】\n\(critiqueContent)"
        } else {
            systemPrompt = "Fix the issues raised in the critique and output the complete improved answer."
            userPrompt = "Question: \(truncate(input.query, to: 300))\n\n[Current Answer]\n\(solveContent)\n\n[Critique]\n\(critiqueContent)"
        }

        let raw = try await streamingGenerate(
            stageName: name,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            context: context
        )

        let output = parseOutput(raw: raw, kind: .revise)

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
        await context.workingMemory.store(output: output, for: name)

        return output
    }
}
