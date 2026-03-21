import Foundation

// MARK: - Retrieve Memory Stage

public struct RetrieveMemoryStage: Stage {
    public let kind: StageKind = .retrieveMemory
    public let name = "RetrieveMemory"
    public let purpose = "外部メモリーから関連情報を取得する"

    private let searchPolicy: MemorySearchPolicy

    public init(searchPolicy: MemorySearchPolicy = .default) {
        self.searchPolicy = searchPolicy
    }

    public func execute(input: StageInput, context: PipelineContext) async throws -> StageOutput {
        await context.traceCollector.record(
            event: .stageStarted(stage: name, kind: kind, input: input.query)
        )

        let query = MemorySearchQuery(
            text: input.query,
            kinds: searchPolicy.searchKinds,
            limit: searchPolicy.topK,
            minPriority: searchPolicy.minPriority
        )

        let entries: [MemoryEntry]
        do {
            entries = try await context.longTermMemory.search(query: query)
        } catch {
            throw StageError.memoryRetrievalFailed(underlying: error)
        }

        await context.traceCollector.record(
            event: .memoryRetrieved(stage: name, entries: entries)
        )

        let content: String
        if entries.isEmpty {
            content = "関連するメモリーは見つかりませんでした。"
        } else {
            content = entries.enumerated().map { idx, entry in
                "[\(idx + 1)] [\(entry.kind.rawValue)] \(entry.content)"
            }.joined(separator: "\n\n")
        }

        let output = StageOutput(
            stageKind: .retrieveMemory,
            content: content,
            bulletPoints: entries.map { "[\($0.kind.rawValue)] \($0.content.prefix(100))..." },
            confidence: entries.isEmpty ? 0.1 : 0.8,
            metadata: ["hitCount": "\(entries.count)"]
        )

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
        await context.workingMemory.store(output: output, for: name)

        return output
    }
}
