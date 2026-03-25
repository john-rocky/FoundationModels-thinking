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
            systemPrompt = "回答の誤りや見落としを指摘してください。反例があれば示すこと。"
            userPrompt = "質問: \(truncate(input.query, to: 300))\n\n【回答】\n\(solveContent)"
        } else {
            systemPrompt = "Point out errors or oversights in the answer. Provide counterexamples if any."
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
