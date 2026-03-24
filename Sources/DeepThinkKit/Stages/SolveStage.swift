import Foundation

// MARK: - Solve Stage

public struct SolveStage: Stage {
    public let kind: StageKind = .solve
    public let name: String
    public let purpose = "Generate the main answer based on the plan and analysis results"

    public init(name: String = "Solve") {
        self.name = name
    }

    public func execute(input: StageInput, context: PipelineContext) async throws -> StageOutput {
        await context.traceCollector.record(
            event: .stageStarted(stage: name, kind: kind, input: input.query)
        )

        let analysis = input.previousOutputs["Analyze"].map { summarizeForNextStage($0) } ?? ""
        let plan = input.previousOutputs["Plan"].map { summarizeForNextStage($0) } ?? ""

        let systemPrompt: String
        var userPrompt: String

        if context.language.isJapanese {
            systemPrompt = "以下の分析と方針に従って回答を生成してください。分析で特定された観点を漏れなくカバーし、方針の手順に沿って構成すること。確信度(0.0-1.0)も末尾に。"
            userPrompt = "質問: \(truncate(input.query, to: 500))"
            if !analysis.isEmpty { userPrompt += "\n\n【分析結果】\n\(analysis)" }
            if !plan.isEmpty { userPrompt += "\n\n【回答方針】\n\(plan)" }
        } else {
            systemPrompt = "Generate an answer following the analysis and plan below. Cover all perspectives identified in the analysis and structure according to the plan. Include confidence (0.0-1.0) at the end."
            userPrompt = "Question: \(truncate(input.query, to: 500))"
            if !analysis.isEmpty { userPrompt += "\n\n[Analysis]\n\(analysis)" }
            if !plan.isEmpty { userPrompt += "\n\n[Plan]\n\(plan)" }
        }

        let raw = try await streamingGenerate(
            stageName: name,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            context: context
        )

        let output = parseOutput(raw: raw, kind: .solve)

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
        await context.workingMemory.store(output: output, for: name)

        return output
    }
}
