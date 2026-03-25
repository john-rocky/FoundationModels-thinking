import Foundation

// MARK: - Critique Stage

public struct CritiqueStage: Stage {
    public let kind: StageKind = .critique
    public let name = "Critique"
    public let purpose = "Extract weaknesses, ambiguities, contradictions, and lack of evidence from the main answer"

    public init() {}

    public func execute(input: StageInput, context: PipelineContext) async throws -> StageOutput {
        await context.traceCollector.record(
            event: .stageStarted(stage: name, kind: kind, input: input.query)
        )

        let solveContent = input.previousOutputs.first(where: {
            $0.value.stageKind == .solve || $0.value.stageKind == .revise
        }).map { summarizeForNextStage($0.value) } ?? ""

        let systemPrompt: String
        let userPrompt: String

        if context.language.isJapanese {
            systemPrompt = "あなたは厳密な学術査読者です。以下の回答を慎重に検証してください。(1)回答を反証する反例がないか検討してください (2)不変量、パリティ議論、隠れた制約が見落とされていないか確認してください (3)異なる結論が成り立つ条件は何ですか？ (4)反証できない場合は、なぜ回答が正しいか厳密に説明してください。具体的なフィードバックを。確信度(0.0-1.0)も末尾に。"
            userPrompt = "質問: \(truncate(input.query, to: 300))\n\n【回答】\n\(solveContent)"
        } else {
            systemPrompt = "You are a rigorous academic reviewer conducting peer review. Your task: (1) Search for counterexamples that would disprove the answer (2) Verify whether invariants, parity arguments, or hidden constraints have been properly addressed (3) Consider what conditions would lead to a different conclusion (4) If the answer withstands scrutiny, explain precisely why it is correct. Provide specific, substantive feedback. Confidence (0.0-1.0) at the end."
            userPrompt = "Question: \(truncate(input.query, to: 300))\n\n[Answer]\n\(solveContent)"
        }

        let raw = try await streamingGenerate(
            stageName: name,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            context: context
        )

        let output = parseOutput(raw: raw, kind: .critique)

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
        await context.workingMemory.store(output: output, for: name)

        return output
    }
}
