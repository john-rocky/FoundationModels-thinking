import Foundation
import DeepThinkKit

// MARK: - Chat Message

struct ChatMessage: Identifiable, Sendable {
    let id: String
    let role: MessageRole
    let content: String
    let timestamp: Date
    let pipelineResult: PipelineResult?

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
        self.pipelineResult = pipelineResult
    }
}

enum MessageRole: String, Sendable {
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

struct Conversation: Identifiable, Sendable {
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
