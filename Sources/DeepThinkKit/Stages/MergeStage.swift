import Foundation

// MARK: - Merge Stage (for Branch & Merge Pipeline)

public struct MergeStage: Stage {
    public let kind: StageKind = .merge
    public let name = "Merge"
    public let purpose = "複数の解答を統合して一つの回答にまとめる"

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

        let systemPrompt = "複数の回答を統合して最も質の高い1つの回答を作成してください。簡潔に。確信度(0.0-1.0)も。"

        let userPrompt = """
        質問: \(truncate(input.query, to: 200))

        \(solveOutputs)
        """

        let raw = try await context.modelProvider.generate(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
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
    public let purpose = "複数回答の共通性・多数性から最終答えを導く"

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

        let systemPrompt = "複数の回答を比較し、共通点から最も信頼性の高い回答を導いてください。簡潔に。確信度(0.0-1.0)も。"

        let userPrompt = """
        質問: \(truncate(input.query, to: 200))

        \(solveOutputs)
        """

        let raw = try await context.modelProvider.generate(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )

        let output = parseOutput(raw: raw, kind: .aggregate)

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
        await context.workingMemory.store(output: output, for: name)

        return output
    }
}
