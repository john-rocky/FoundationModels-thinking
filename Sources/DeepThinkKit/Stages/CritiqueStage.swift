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
            systemPrompt = "あなたは懐疑的な査読者です。以下の回答が間違っていると仮定してください。(1)回答を反証する反例を見つけよ (2)見落とされた不変量、パリティ議論、隠れた制約がないか確認せよ (3)正反対の結論が成り立つには何が必要か？ (4)反証できない場合のみ、なぜ回答が正しいか厳密に説明せよ。具体的に。単に同意するな。確信度(0.0-1.0)も末尾に。"
            userPrompt = "質問: \(truncate(input.query, to: 300))\n\n【回答】\n\(solveContent)"
        } else {
            systemPrompt = "You are a skeptical reviewer. ASSUME the answer below is WRONG. Your job: (1) Try to find a counterexample that disproves the answer (2) Check for missing invariants, parity arguments, or hidden constraints (3) What would need to be true for the OPPOSITE conclusion to hold? (4) Only if you cannot disprove the answer, explain exactly why it must be correct. Be specific. Do not just agree. Confidence (0.0-1.0) at the end."
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
