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

        let systemPrompt = localizedSystemPrompt(
            "Based on the analysis, design answer steps as bullet points. Do not write the answer itself.",
            language: context.language
        )
        let userPrompt = "Question: \(truncate(input.query, to: 400))\n\n[Analysis]\n\(analysis)"

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
