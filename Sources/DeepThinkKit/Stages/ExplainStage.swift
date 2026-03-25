import Foundation

// MARK: - Explain Stage (LLM)

public struct ExplainStage: Stage {
    public let kind: StageKind = .finalize
    public let name = "Explain"
    public let purpose = "Generate a clear human-readable explanation of the verified solution"

    public init() {}

    public func execute(input: StageInput, context: PipelineContext) async throws -> StageOutput {
        await context.traceCollector.record(
            event: .stageStarted(stage: name, kind: kind, input: input.query)
        )

        let solveOutput = input.previousOutputs["Solve"]
        let solverStatus = solveOutput?.metadata["solver_status"] ?? "unknown"

        // If solver failed, fall back to direct LLM answer
        if solverStatus == "parse_failed" {
            let systemPrompt = context.language.isJapanese
                ? "質問に直接回答してください。"
                : "Answer the question directly."
            let raw = try await streamingGenerate(
                stageName: name,
                systemPrompt: systemPrompt,
                userPrompt: truncate(input.query, to: 600),
                context: context
            )
            let output = parseOutput(raw: raw, kind: .finalize)
            await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
            return output
        }

        let solutionText = solveOutput?.content ?? ""
        let systemPrompt: String
        let userPrompt: String

        if context.language.isJapanese {
            systemPrompt = "検証済みの解を元に、回答を分かりやすく説明してください。"
            userPrompt = "問題: \(truncate(input.query, to: 400))\n\n【検証済み解】\n\(solutionText)"
        } else {
            systemPrompt = "Explain the verified solution clearly to answer the original problem."
            userPrompt = "Problem: \(truncate(input.query, to: 400))\n\n[Verified Solution]\n\(solutionText)"
        }

        let raw = try await streamingGenerate(
            stageName: name,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            context: context
        )

        let output = parseOutput(raw: raw, kind: .finalize)
        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
        return output
    }
}
