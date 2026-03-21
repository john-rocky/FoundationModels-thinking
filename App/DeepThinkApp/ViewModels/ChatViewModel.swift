import Foundation
import SwiftUI
import DeepThinkKit

@Observable
@MainActor
final class ChatViewModel {
    var conversations: [Conversation] = []
    var selectedConversationId: String?
    var inputText = ""
    var isProcessing = false
    var selectedPipelineKind: PipelineKind = .sequential
    var showTrace = false
    var showMemoryBrowser = false
    var errorMessage: String?

    private let longTermMemory = LongTermMemory()

    var currentConversation: Conversation? {
        get {
            guard let id = selectedConversationId else { return nil }
            return conversations.first { $0.id == id }
        }
        set {
            guard let conv = newValue,
                  let index = conversations.firstIndex(where: { $0.id == conv.id }) else { return }
            conversations[index] = conv
        }
    }

    init() {
        createNewConversation()
    }

    func createNewConversation() {
        let conversation = Conversation(pipelineKind: selectedPipelineKind)
        conversations.insert(conversation, at: 0)
        selectedConversationId = conversation.id
    }

    func deleteConversation(id: String) {
        conversations.removeAll { $0.id == id }
        if selectedConversationId == id {
            selectedConversationId = conversations.first?.id
        }
    }

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isProcessing else { return }

        inputText = ""
        errorMessage = nil

        guard var conversation = currentConversation else { return }

        let userMessage = ChatMessage(role: .user, content: text)
        conversation.messages.append(userMessage)

        if conversation.messages.count == 1 {
            conversation.title = String(text.prefix(40))
        }

        currentConversation = conversation

        isProcessing = true

        Task {
            await processMessage(text: text, conversationId: conversation.id)
        }
    }

    private func processMessage(text: String, conversationId: String) async {
        defer { isProcessing = false }

        do {
            let modelProvider = FoundationModelProvider()
            let context = PipelineContext(
                modelProvider: modelProvider,
                longTermMemory: longTermMemory
            )

            let pipeline = PipelineFactory.create(
                kind: selectedPipelineKind
            )

            let result = try await pipeline.execute(query: text, context: context)

            let assistantMessage = ChatMessage(
                role: .assistant,
                content: result.finalOutput.content,
                pipelineResult: result
            )

            if var conversation = conversations.first(where: { $0.id == conversationId }) {
                conversation.messages.append(assistantMessage)
                if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
                    conversations[index] = conversation
                }
            }

            // Auto-save to long-term memory if confidence is high
            if result.finalOutput.confidence >= 0.7 {
                let entry = MemoryEntry(
                    kind: .summary,
                    content: result.finalOutput.content,
                    tags: ["auto-save", selectedPipelineKind.rawValue],
                    source: "pipeline:\(pipeline.name)"
                )
                try? await longTermMemory.save(entry)
            }

        } catch {
            let description: String
            if let stageError = error as? StageError {
                description = stageError.errorDescription ?? "\(stageError)"
            } else {
                description = "\(error)"
            }
            errorMessage = description
            let errorMsg = ChatMessage(
                role: .system,
                content: description
            )
            if var conversation = conversations.first(where: { $0.id == conversationId }) {
                conversation.messages.append(errorMsg)
                if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
                    conversations[index] = conversation
                }
            }
        }
    }
}
