import Foundation

// MARK: - Session Memory

public actor SessionMemory {
    private var entries: [MemoryEntry] = []
    private let maxEntries: Int

    public init(maxEntries: Int = 50) {
        self.maxEntries = maxEntries
    }

    public func add(_ entry: MemoryEntry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    public func addMessage(role: String, content: String) {
        let entry = MemoryEntry(
            kind: .intermediate,
            content: content,
            tags: [role],
            source: "session"
        )
        add(entry)
    }

    public func recentEntries(limit: Int = 10) -> [MemoryEntry] {
        Array(entries.suffix(limit))
    }

    public func allEntries() -> [MemoryEntry] {
        entries
    }

    public func clear() {
        entries.removeAll()
    }
}
