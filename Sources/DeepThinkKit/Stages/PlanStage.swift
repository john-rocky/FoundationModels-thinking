import Foundation

// MARK: - Plan Stage

public struct PlanStage: Stage {
    public let kind: StageKind = .plan
    public let name = "Plan"
    public let purpose = "Organize the approach, required perspectives, and processing order for the final answer"

    public init() {}

    public func execute(input: StageInput, context: PipelineContext) async throws -> StageOutput {
        await context.traceCollector.record(
            event: .stageStarted(stage: name, kind: kind, input: input.query)
        )

        let analysis = input.previousOutputs["Analyze"].map { summarizeForNextStage($0) } ?? ""

        let systemPrompt: String
        let userPrompt: String

        if context.language.isJapanese {
            systemPrompt = "あなたは回答設計者です。分析結果を踏まえ、最良の回答を組み立てるための具体的な手順を箇条書きで設計してください。各手順は「何を、どう述べるか」を明示すること。回答本文は書かないこと。確信度(0.0-1.0)も末尾に。"
            userPrompt = "質問: \(truncate(input.query, to: 400))\n\n【分析結果】\n\(analysis)"
        } else {
            systemPrompt = "You are a response architect. Based on the analysis, design concrete steps as bullet points to construct the best answer. Each step must specify what to say and how. DO NOT write the answer itself. Include confidence (0.0-1.0) at the end."
            userPrompt = "Question: \(truncate(input.query, to: 400))\n\n[Analysis]\n\(analysis)"
        }

        let raw = try await streamingGenerate(
            stageName: name,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            context: context
        )

        let output = parseOutput(raw: raw, kind: .plan)

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
        await context.workingMemory.store(output: output, for: name)

        return output
    }
}
