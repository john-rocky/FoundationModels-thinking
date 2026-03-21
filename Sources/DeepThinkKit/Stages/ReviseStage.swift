import Foundation

// MARK: - Revise Stage

public struct ReviseStage: Stage {
    public let kind: StageKind = .revise
    public let name = "Revise"
    public let purpose = "critique 結果をもとに回答を修正する"

    public init() {}

    public func execute(input: StageInput, context: PipelineContext) async throws -> StageOutput {
        await context.traceCollector.record(
            event: .stageStarted(stage: name, kind: kind, input: input.query)
        )

        let solveContent = input.previousOutputs.first(where: {
            $0.value.stageKind == .solve || $0.value.stageKind == .revise
        }).map { summarizeForNextStage($0.value) } ?? ""

        let critiqueContent = input.previousOutputs["Critique"].map { summarizeForNextStage($0) } ?? ""

        let systemPrompt = "批評をもとに回答を改善してください。改善後の回答を簡潔に。確信度(0.0-1.0)も。"

        let userPrompt = """
        質問: \(truncate(input.query, to: 200))

        現在の回答: \(solveContent)

        批評: \(critiqueContent)
        """

        let raw = try await context.modelProvider.generate(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )

        let output = parseOutput(raw: raw, kind: .revise)

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
        await context.workingMemory.store(output: output, for: name)

        return output
    }
}
