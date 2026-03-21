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
            .map { "【\($0.key)】\n\($0.value.content)" }
            .joined(separator: "\n\n---\n\n")

        let systemPrompt = """
        あなたは統合の専門家です。複数の異なる観点からの回答を統合して、
        最も包括的で質の高い回答を作成してください。

        ## 統合回答
        (本文)

        ## 各観点からの貢献
        - (どの回答からどの要素を採用したか)

        ## 確信度
        (0.0〜1.0の数値)
        """

        let userPrompt = """
        以下の複数の回答を統合してください:

        【元の質問】
        \(input.query)

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
            .map { "【回答\($0.offset + 1)】\n\($0.element.value.content)" }
            .joined(separator: "\n\n---\n\n")

        let systemPrompt = """
        あなたは合意形成の専門家です。複数の独立した回答を比較し、
        共通する要素や多数派の見解を特定して、最も信頼性の高い回答を導いてください。

        ## 共通要素
        - (全回答に共通する点)

        ## 相違点
        - (回答間で異なる点)

        ## 最終回答
        (共通性と多数性に基づく回答)

        ## 確信度
        (0.0〜1.0の数値。一致度が高いほど高い値)
        """

        let userPrompt = """
        以下の複数回答を分析し、最も信頼性の高い回答を導いてください:

        【元の質問】
        \(input.query)

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
