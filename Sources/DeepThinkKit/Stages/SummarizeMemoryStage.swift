import Foundation

// MARK: - Summarize Memory Stage

public struct SummarizeMemoryStage: Stage {
    public let kind: StageKind = .summarizeMemory
    public let name = "SummarizeMemory"
    public let purpose = "Compress long or multiple memories into concise notes for re-injection"

    public init() {}

    public func execute(input: StageInput, context: PipelineContext) async throws -> StageOutput {
        await context.traceCollector.record(
            event: .stageStarted(stage: name, kind: kind, input: input.query)
        )

        let memoryContent = input.memoryContext.prefix(5).map { entry in
            "[\(entry.kind.rawValue)] \(truncate(entry.content, to: 100))"
        }.joined(separator: "\n")

        guard !memoryContent.isEmpty else {
            let content = "No memory to summarize."
            let output = StageOutput(
                stageKind: .summarizeMemory,
                content: content,
                confidence: 1.0
            )
            await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
            return output
        }

        let systemPrompt = localizedSystemPrompt(
            "Summarize the memory concisely, keeping only information relevant to the current task. Use bullet points.",
            language: context.language
        )
        let userPrompt = "Task: \(truncate(input.query, to: 200))\n\nMemory:\n\(memoryContent)"

        let raw = try await streamingGenerate(
            stageName: name,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            context: context
        )

        let output = parseOutput(raw: raw, kind: .summarizeMemory)

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
        await context.workingMemory.store(output: output, for: name)

        return output
    }
}
