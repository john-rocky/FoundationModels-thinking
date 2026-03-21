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

        let memoryContent = input.memoryContext.map { entry in
            "[\(entry.kind.rawValue)] \(entry.content)"
        }.joined(separator: "\n\n")

        guard !memoryContent.isEmpty else {
            let output = StageOutput(
                stageKind: .summarizeMemory,
                content: "要約対象のメモリーがありません。",
                confidence: 1.0
            )
            await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
            return output
        }

        let systemPrompt = """
        あなたは要約の専門家です。
        複数のメモリーエントリを、現在のタスクに関連する情報だけを残して簡潔に要約してください。
        要約は箇条書きで、各項目は1-2文以内にしてください。
        """

        let userPrompt = """
        以下のメモリーを要約してください:

        【現在のタスク】
        \(input.query)

        【メモリー】
        \(memoryContent)
        """

        let raw = try await context.modelProvider.generate(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )

        let output = parseOutput(raw: raw, kind: .summarizeMemory)

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
        await context.workingMemory.store(output: output, for: name)

        return output
    }
}
