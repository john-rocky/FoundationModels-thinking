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

        let systemPrompt = "以下の複数回答から、各回答の最も優れた部分を選んで統合してください。共通する内容は確度が高いとみなし、矛盾する部分は最も根拠のある方を採用すること。確信度(0.0-1.0)も末尾に。"

        let userPrompt = """
        質問: \(truncate(input.query, to: 300))

        【各回答】
        \(solveOutputs)
        """

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

        let systemPrompt = "以下の複数回答を比較分析してください。多数の回答が一致する内容を最も信頼し、独自の主張は根拠を検証して採否を判断すること。最終回答を出力してください。確信度(0.0-1.0)も末尾に。"

        let userPrompt = """
        質問: \(truncate(input.query, to: 300))

        【各回答】
        \(solveOutputs)
        """

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
