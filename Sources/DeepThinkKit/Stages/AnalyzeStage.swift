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
            systemPrompt = "あなたは問題分析の専門家です。質問を分解し、以下を箇条書きで出力してください：(1)核心的な問い (2)必要な知識領域 (3)隠れた前提や制約 (4)曖昧な点。回答は書かないこと。確信度(0.0-1.0)も末尾に。"
        } else {
            systemPrompt = "You are an expert problem analyst. Decompose the question and output the following as bullet points: (1) Core question (2) Required knowledge domains (3) Hidden assumptions or constraints (4) Ambiguous points. DO NOT write the answer. Include confidence (0.0-1.0) at the end."
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
