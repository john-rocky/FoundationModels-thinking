import Foundation

// MARK: - Long-Term Memory

public actor LongTermMemory {
    private let store: any MemoryStore
    private var cache: [MemoryEntry] = []
    private var loaded = false

    public init(store: (any MemoryStore)? = nil) {
        self.store = store ?? FileMemoryStore()
    }

    public func save(_ entry: MemoryEntry) async throws {
        try await store.save(entry)
        cache.append(entry)
    }

    public func search(query: MemorySearchQuery) async throws -> [MemoryEntry] {
        try await ensureLoaded()
        return filterEntries(cache, with: query)
    }

    public func allEntries() async throws -> [MemoryEntry] {
        try await ensureLoaded()
        return cache
    }

    public func delete(id: String) async throws {
        try await store.delete(id: id)
        cache.removeAll { $0.id == id }
    }

    public func clear() async throws {
        let all = try await store.loadAll()
        for entry in all {
            try await store.delete(id: entry.id)
        }
        cache.removeAll()
    }

    private func ensureLoaded() async throws {
        guard !loaded else { return }
        cache = try await store.loadAll()
        loaded = true
    }

    private func filterEntries(_ entries: [MemoryEntry], with query: MemorySearchQuery) -> [MemoryEntry] {
        var results = entries

        if let kinds = query.kinds {
            results = results.filter { kinds.contains($0.kind) }
        }

        if let tags = query.tags {
            results = results.filter { entry in
                tags.contains(where: { entry.tags.contains($0) })
            }
        }

        if let minPriority = query.minPriority {
            results = results.filter { $0.priority >= minPriority }
        }

        if let text = query.text, !text.isEmpty {
            let lowered = text.lowercased()
            results = results.filter {
                $0.content.lowercased().contains(lowered) ||
                $0.tags.contains(where: { $0.lowercased().contains(lowered) })
            }
            results.sort { lhs, rhs in
                let lScore = relevanceScore(entry: lhs, query: lowered)
                let rScore = relevanceScore(entry: rhs, query: lowered)
                return lScore > rScore
            }
        }

        results.sort { $0.priority > $1.priority }

        return Array(results.prefix(query.limit))
    }

    private func relevanceScore(entry: MemoryEntry, query: String) -> Double {
        var score = 0.0
        let content = entry.content.lowercased()
        if content.contains(query) { score += 1.0 }
        let words = query.split(separator: " ")
        for word in words {
            if content.contains(word) { score += 0.5 }
        }
        if entry.tags.contains(where: { $0.lowercased().contains(query) }) { score += 0.5 }
        score += Double(entry.priority.rawValue) * 0.1
        return score
    }
}
