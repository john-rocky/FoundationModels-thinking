import Foundation

// MARK: - Working Memory

public actor WorkingMemory {
    private var entries: [String: StageOutput] = [:]
    private var intermediates: [MemoryEntry] = []

    public init() {}

    public func store(output: StageOutput, for stageId: String) {
        entries[stageId] = output
    }

    public func retrieve(for stageId: String) -> StageOutput? {
        entries[stageId]
    }

    public func allOutputs() -> [String: StageOutput] {
        entries
    }

    public func addIntermediate(_ entry: MemoryEntry) {
        intermediates.append(entry)
    }

    public func allIntermediates() -> [MemoryEntry] {
        intermediates
    }

    public func clear() {
        entries.removeAll()
        intermediates.removeAll()
    }
}
