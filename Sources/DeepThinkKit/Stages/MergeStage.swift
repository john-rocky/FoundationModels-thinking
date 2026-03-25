import Foundation

// MARK: - Merge Stage (for Branch & Merge Pipeline)

public struct MergeStage: Stage {
    public let kind: StageKind = .merge
    public let name = "Merge"
    public let purpose = "Integrate multiple answers into a single unified response"

    public init() {}

    public func execute(input: StageInput, context: PipelineContext) async throws -> StageOutput {
        await context.traceCollector.record(
            event: .stageStarted(stage: name, kind: kind, input: input.query)
        )

        let solveOutputs = input.previousOutputs
            .filter { $0.value.stageKind == .solve }
            .sorted { $0.key < $1.key }
            .map { "[\($0.key)] \(summarizeForNextStage($0.value))" }
            .joined(separator: "\n\n")

        let systemPrompt: String
        let userPrompt: String

        if context.language.isJapanese {
            systemPrompt = "複数の回答から最も優れた部分を選び、一つの回答に統合してください。"
            userPrompt = "質問: \(truncate(input.query, to: 300))\n\n【各回答】\n\(solveOutputs)"
        } else {
            systemPrompt = "Select the best parts from each answer and integrate into one."
            userPrompt = "Question: \(truncate(input.query, to: 300))\n\n[Answers]\n\(solveOutputs)"
        }

        let raw = try await streamingGenerate(
            stageName: name,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            context: context
        )

        let output = parseOutput(raw: raw, kind: .merge)

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
        await context.workingMemory.store(output: output, for: name)

        return output
    }
}

// MARK: - Aggregate Stage (for Self-Consistency Pipeline)

public struct AggregateStage: Stage {
    public let kind: StageKind = .aggregate
    public let name = "Aggregate"
    public let purpose = "Derive the final answer from commonality and majority across multiple answers"

    public init() {}

    public func execute(input: StageInput, context: PipelineContext) async throws -> StageOutput {
        await context.traceCollector.record(
            event: .stageStarted(stage: name, kind: kind, input: input.query)
        )

        let solveOutputs = input.previousOutputs
            .filter { $0.value.stageKind == .solve }
            .sorted { $0.key < $1.key }
            .enumerated()
            .map { "[\($0.offset + 1)] \(summarizeForNextStage($0.element.value))" }
            .joined(separator: "\n\n")

        let systemPrompt: String
        let userPrompt: String

        if context.language.isJapanese {
            systemPrompt = "複数の回答を比較し、多数が一致する内容を信頼して最終回答を出力してください。"
            userPrompt = "質問: \(truncate(input.query, to: 300))\n\n【各回答】\n\(solveOutputs)"
        } else {
            systemPrompt = "Compare the answers. Trust majority consensus and output the final answer."
            userPrompt = "Question: \(truncate(input.query, to: 300))\n\n[Answers]\n\(solveOutputs)"
        }

        let raw = try await streamingGenerate(
            stageName: name,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            context: context
        )

        let output = parseOutput(raw: raw, kind: .aggregate)

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
        await context.workingMemory.store(output: output, for: name)

        return output
    }
}
