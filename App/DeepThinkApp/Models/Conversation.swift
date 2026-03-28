import Foundation
import DeepThinkKit

// MARK: - Chat Message

struct ChatMessage: Identifiable, Sendable, Codable {
    let id: String
    let role: MessageRole
    let content: String
    let timestamp: Date

    // Pipeline metadata persisted for UI display
    let pipelineName: String?
    let pipelineConfidence: Double?
    let pipelineDuration: TimeInterval?

    // Transient: full result only available during current session
    var pipelineResult: PipelineResult? {
        get { _pipelineResult }
    }
    private var _pipelineResult: PipelineResult?

    enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp
        case pipelineName, pipelineConfidence, pipelineDuration
    }

    init(
        id: String = UUID().uuidString,
        role: MessageRole,
        content: String,
        timestamp: Date = .now,
        pipelineResult: PipelineResult? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self._pipelineResult = pipelineResult
        self.pipelineName = pipelineResult?.pipelineName
        self.pipelineConfidence = pipelineResult?.finalOutput.confidence
        self.pipelineDuration = pipelineResult?.totalDuration
    }
}

enum MessageRole: String, Sendable, Codable {
    case user
    case assistant
    case system
}

// MARK: - Thinking Step

struct ThinkingStep: Identifiable {
    let id: String
    let stageName: String
    let stageKind: StageKind
    let index: Int
    var status: StepStatus
    var output: StageOutput?
    var branchOutputs: [String: StageOutput]
    var streamingContent: String
    enum StepStatus {
        case running
        case completed
        case failed(String)
        case retrying(attempt: Int)
    }

    init(
        stageName: String,
        stageKind: StageKind,
        index: Int
    ) {
        self.id = UUID().uuidString
        self.stageName = stageName
        self.stageKind = stageKind
        self.index = index
        self.status = .running
        self.output = nil
        self.branchOutputs = [:]
        self.streamingContent = ""
    }
}

// MARK: - Conversation

struct Conversation: Identifiable, Sendable, Codable {
    let id: String
    var title: String
    var messages: [ChatMessage]
    var pipelineKind: PipelineKind
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        title: String = "New Conversation",
        messages: [ChatMessage] = [],
        pipelineKind: PipelineKind = .sequential,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.pipelineKind = pipelineKind
        self.createdAt = createdAt
    }
}

// MARK: - Conversation Persistence

enum ConversationStore {
    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeepThinkKit", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("conversations.json")
    }

    static func save(_ conversations: [Conversation]) {
        do {
            let data = try JSONEncoder().encode(conversations)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save conversations: \(error)")
        }
    }

    static func load() -> [Conversation] {
        guard let data = try? Data(contentsOf: fileURL),
              let conversations = try? JSONDecoder().decode([Conversation].self, from: data) else {
            return []
        }
        return conversations
    }
}
