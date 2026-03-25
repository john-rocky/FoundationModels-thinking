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

        let systemPrompt: String
        if context.language.isJapanese {
            systemPrompt = "質問を分解し、核心・前提・隠れた制約を箇条書きで。回答は書かないこと。"
        } else {
            systemPrompt = "Decompose the question. List the core problem, assumptions, and hidden constraints. Do not answer."
        }

        var userPrompt = truncate(input.query, to: 1000)
        if !input.memoryContext.isEmpty {
            userPrompt += formatMemoryContext(input.memoryContext, language: context.language)
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
