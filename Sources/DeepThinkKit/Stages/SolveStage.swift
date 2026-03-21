import Foundation

// MARK: - Solve Stage

public struct SolveStage: Stage {
    public let kind: StageKind = .solve
    public let name: String
    public let purpose = "plan や analyze 結果をもとに主回答を生成する"

    public init(name: String = "Solve") {
        self.name = name
    }

    public func execute(input: StageInput, context: PipelineContext) async throws -> StageOutput {
        await context.traceCollector.record(
            event: .stageStarted(stage: name, kind: kind, input: input.query)
        )

        let analysis = input.previousOutputs["Analyze"].map { summarizeForNextStage($0) } ?? ""
        let plan = input.previousOutputs["Plan"].map { summarizeForNextStage($0) } ?? ""

        let systemPrompt = "以下の分析と方針に従って回答を生成してください。分析で特定された観点を漏れなくカバーし、方針の手順に沿って構成すること。分析・方針を無視して独自に回答しないこと。確信度(0.0-1.0)も末尾に。"

        var userPrompt = "質問: \(truncate(input.query, to: 500))"
        if !analysis.isEmpty {
            userPrompt += "\n\n【分析結果】\n\(analysis)"
        }
        if !plan.isEmpty {
            userPrompt += "\n\n【回答方針】\n\(plan)"
        }

        let raw = try await context.modelProvider.generate(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )

        let output = parseOutput(raw: raw, kind: .solve)

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
        await context.workingMemory.store(output: output, for: name)

        return output
    }
}
