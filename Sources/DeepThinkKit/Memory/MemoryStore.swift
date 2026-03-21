import Foundation

// MARK: - Memory Store Protocol

public protocol MemoryStore: Sendable {
    func save(_ entry: MemoryEntry) async throws
    func loadAll() async throws -> [MemoryEntry]
    func load(id: String) async throws -> MemoryEntry?
    func delete(id: String) async throws
}

// MARK: - File-Based Memory Store

public final class FileMemoryStore: MemoryStore, @unchecked Sendable {
    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = NSLock()

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.directory = appSupport.appendingPathComponent("DeepThinkKit/Memory", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    public func save(_ entry: MemoryEntry) async throws {
        let data = try encoder.encode(entry)
        let fileURL = directory.appendingPathComponent("\(entry.id).json")
        try data.write(to: fileURL, options: .atomic)
    }

    public func loadAll() async throws -> [MemoryEntry] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        let files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }

        var entries: [MemoryEntry] = []
        for file in files {
            let data = try Data(contentsOf: file)
            if let entry = try? decoder.decode(MemoryEntry.self, from: data) {
                entries.append(entry)
            }
        }
        return entries.sorted { $0.createdAt < $1.createdAt }
    }

    public func load(id: String) async throws -> MemoryEntry? {
        let fileURL = directory.appendingPathComponent("\(id).json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(MemoryEntry.self, from: data)
    }

    public func delete(id: String) async throws {
        let fileURL = directory.appendingPathComponent("\(id).json")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}

// MARK: - In-Memory Store (for testing)

public actor InMemoryStore: MemoryStore {
    private var entries: [String: MemoryEntry] = [:]

    public init() {}

    public func save(_ entry: MemoryEntry) async throws {
        entries[entry.id] = entry
    }

    public func loadAll() async throws -> [MemoryEntry] {
        Array(entries.values).sorted { $0.createdAt < $1.createdAt }
    }

    public func load(id: String) async throws -> MemoryEntry? {
        entries[id]
    }

    public func delete(id: String) async throws {
        entries.removeValue(forKey: id)
    }
}
