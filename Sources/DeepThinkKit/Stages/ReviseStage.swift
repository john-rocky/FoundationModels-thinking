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
            systemPrompt = "修正前に、分析結果の非自明な構造や不変量を再確認し、現在の回答が見落としていないか確認すること。批評で指摘された各問題点を一つずつ修正し、改善後の完全な回答を出力してください。批評にない部分は元の回答を維持すること。何を修正したか末尾に簡潔に記載。確信度(0.0-1.0)も末尾に。"
            userPrompt = "質問: \(truncate(input.query, to: 300))\n\n【現在の回答】\n\(solveContent)\n\n【批評・改善指示】\n\(critiqueContent)"
        } else {
            systemPrompt = "Before fixing, re-read the analysis for any hidden structure or invariants that the current answer may have missed. Fix each issue raised in the critique one by one and output the complete improved answer. Keep parts not mentioned in the critique unchanged. Briefly list what you fixed at the end. Confidence (0.0-1.0) at the end."
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
