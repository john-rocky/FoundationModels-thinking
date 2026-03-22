import Foundation

// MARK: - Summarize Memory Stage

public struct SummarizeMemoryStage: Stage {
    public let kind: StageKind = .summarizeMemory
    public let name = "SummarizeMemory"
    public let purpose = "長い記憶や複数記憶を短い再注入用メモに圧縮する"

    public init() {}

    public func execute(input: StageInput, context: PipelineContext) async throws -> StageOutput {
        await context.traceCollector.record(
            event: .stageStarted(stage: name, kind: kind, input: input.query)
        )

        let memoryContent = input.memoryContext.prefix(5).map { entry in
            "[\(entry.kind.rawValue)] \(truncate(entry.content, to: 100))"
        }.joined(separator: "\n")

        guard !memoryContent.isEmpty else {
            let output = StageOutput(
                stageKind: .summarizeMemory,
                content: "要約対象のメモリーがありません。",
                confidence: 1.0
            )
            await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
            return output
        }

        let systemPrompt = "メモリーを現在のタスクに関連する情報だけ残して簡潔に要約してください。箇条書きで。"

        let userPrompt = """
        タスク: \(truncate(input.query, to: 200))

        メモリー:
        \(memoryContent)
        """

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
