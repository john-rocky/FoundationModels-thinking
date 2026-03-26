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

        let systemPrompt = localizedSystemPrompt(
            "Generate an answer following the analysis and plan below.",
            language: context.language
        )
        var userPrompt = "Question: \(truncate(input.query, to: 500))"
        if !analysis.isEmpty { userPrompt += "\n\n[Analysis]\n\(analysis)" }
        if !plan.isEmpty { userPrompt += "\n\n[Plan]\n\(plan)" }
        userPrompt += markdownSuffix

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
