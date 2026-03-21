import Foundation

// MARK: - Save Policy

public struct MemorySavePolicy: Sendable {
    public let autoSaveOnFinalize: Bool
    public let saveCritiques: Bool
    public let saveHighPriorityOnly: Bool
    public let compressBeforeSave: Bool
    public let maxContentLength: Int

    public init(
        autoSaveOnFinalize: Bool = true,
        saveCritiques: Bool = true,
        saveHighPriorityOnly: Bool = false,
        compressBeforeSave: Bool = true,
        maxContentLength: Int = 2000
    ) {
        self.autoSaveOnFinalize = autoSaveOnFinalize
        self.saveCritiques = saveCritiques
        self.saveHighPriorityOnly = saveHighPriorityOnly
        self.compressBeforeSave = compressBeforeSave
        self.maxContentLength = maxContentLength
    }

    public static let `default` = MemorySavePolicy()
    public static let minimal = MemorySavePolicy(
        autoSaveOnFinalize: false,
        saveCritiques: false,
        saveHighPriorityOnly: true,
        compressBeforeSave: true,
        maxContentLength: 500
    )
}

// MARK: - Search Policy

public struct MemorySearchPolicy: Sendable {
    public let topK: Int
    public let searchKinds: [MemoryKind]?
    public let minPriority: MemoryPriority
    public let includeRecent: Bool
    public let maxAge: TimeInterval?

    public init(
        topK: Int = 5,
        searchKinds: [MemoryKind]? = nil,
        minPriority: MemoryPriority = .low,
        includeRecent: Bool = true,
        maxAge: TimeInterval? = nil
    ) {
        self.topK = topK
        self.searchKinds = searchKinds
        self.minPriority = minPriority
        self.includeRecent = includeRecent
        self.maxAge = maxAge
    }

    public static let `default` = MemorySearchPolicy()
    public static let factsOnly = MemorySearchPolicy(
        topK: 10,
        searchKinds: [.fact, .decision, .constraint],
        minPriority: .normal
    )
}

// MARK: - Reinjection Policy

public struct MemoryReinjectionPolicy: Sendable {
    public let maxEntries: Int
    public let summarize: Bool
    public let maxTokensEstimate: Int

    public init(
        maxEntries: Int = 5,
        summarize: Bool = true,
        maxTokensEstimate: Int = 500
    ) {
        self.maxEntries = maxEntries
        self.summarize = summarize
        self.maxTokensEstimate = maxTokensEstimate
    }

    public static let `default` = MemoryReinjectionPolicy()
}

// MARK: - Combined Memory Policy

public struct MemoryPolicy: Sendable {
    public let savePolicy: MemorySavePolicy
    public let searchPolicy: MemorySearchPolicy
    public let reinjectionPolicy: MemoryReinjectionPolicy

    public init(
        savePolicy: MemorySavePolicy = .default,
        searchPolicy: MemorySearchPolicy = .default,
        reinjectionPolicy: MemoryReinjectionPolicy = .default
    ) {
        self.savePolicy = savePolicy
        self.searchPolicy = searchPolicy
        self.reinjectionPolicy = reinjectionPolicy
    }

    public static let `default` = MemoryPolicy()
    public static let noMemory = MemoryPolicy(
        savePolicy: .minimal,
        searchPolicy: MemorySearchPolicy(topK: 0),
        reinjectionPolicy: MemoryReinjectionPolicy(maxEntries: 0)
    )
}
