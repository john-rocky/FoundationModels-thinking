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

        let systemPrompt = localizedSystemPrompt(
            "Fix the issues raised in the critique and output the complete improved answer.",
            language: context.language
        )
        let userPrompt = "Question: \(truncate(input.query, to: 300))\n\n[Current Answer]\n\(solveContent)\n\n[Critique]\n\(critiqueContent)"

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
