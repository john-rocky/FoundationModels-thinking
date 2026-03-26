import Foundation

// MARK: - Analyze Stage

public struct AnalyzeStage: Stage {
    public let kind: StageKind = .analyze
    public let name = "Analyze"
    public let purpose = "Decompose input to extract key topics, constraints, unknowns, and candidate tasks"

    public init() {}

    public func execute(input: StageInput, context: PipelineContext) async throws -> StageOutput {
        await context.traceCollector.record(
            event: .stageStarted(stage: name, kind: kind, input: input.query)
        )

        let systemPrompt = localizedSystemPrompt(
            "Decompose the question. List the core problem, assumptions, and hidden constraints. Do not answer.",
            language: context.language
        )

        var userPrompt = truncate(input.query, to: 1000)
        if !input.memoryContext.isEmpty {
            userPrompt += formatMemoryContext(input.memoryContext)
        }

        let raw = try await streamingGenerate(
            stageName: name,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            context: context
        )

        let output = parseOutput(raw: raw, kind: .analyze)

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
        await context.workingMemory.store(output: output, for: name)

        return output
    }
}
