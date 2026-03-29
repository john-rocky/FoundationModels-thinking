import Foundation
import SwiftUI
import DeepThinkKit
import os.log

private let log = Logger(subsystem: "com.deepthink", category: "ChatVM")

@Observable
@MainActor
final class ChatViewModel {
    var conversations: [Conversation] = []
    var selectedConversationId: String?
    var inputText = ""
    var isProcessing = false
    var selectedPipelineKind: PipelineKind = .auto
    var showTrace = false
    var showMemoryBrowser = false
    var errorMessage: String?
    var resolvedPipelineKind: PipelineKind?
    var webSearchEnabled: Bool {
        didSet {
            UserDefaults.standard.set(webSearchEnabled, forKey: "webSearchEnabled")
        }
    }
    var deepSearchEnabled: Bool {
        didSet {
            UserDefaults.standard.set(deepSearchEnabled, forKey: "deepSearchEnabled")
        }
    }
    private var currentTask: Task<Void, Never>?
    private var taskGeneration = 0
    private var lastScrollContentLength = 0

    var appLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(appLanguage.rawValue, forKey: "appLanguage")
        }
    }

    // Streaming thinking state
    var thinkingSteps: [ThinkingStep] = []
    var currentPipelineName: String?
    var expectedStageCount: Int = 0
    var currentStreamingStageName: String?
    var currentStreamingContent: String = ""
    var streamingAnswerContent: String = ""

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
        if let saved = UserDefaults.standard.string(forKey: "appLanguage"),
           let lang = AppLanguage(rawValue: saved) {
            self.appLanguage = lang
        } else {
            self.appLanguage = .japanese
        }
        self.webSearchEnabled = UserDefaults.standard.bool(forKey: "webSearchEnabled")
        self.deepSearchEnabled = UserDefaults.standard.bool(forKey: "deepSearchEnabled")

        // Restore saved conversations
        let saved = ConversationStore.load()
        if saved.isEmpty {
            createNewConversation()
        } else {
            self.conversations = saved
            self.selectedConversationId = saved.first?.id
        }
    }

    private func persistConversations() {
        ConversationStore.save(conversations)
    }

    func createNewConversation() {
        let conversation = Conversation(pipelineKind: selectedPipelineKind)
        conversations.insert(conversation, at: 0)
        selectedConversationId = conversation.id
        persistConversations()
    }

    func deleteConversation(id: String) {
        conversations.removeAll { $0.id == id }
        if selectedConversationId == id {
            selectedConversationId = conversations.first?.id
        }
        persistConversations()
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

        currentTask?.cancel()
        taskGeneration += 1
        let generation = taskGeneration
        log.info("send gen=\(generation)")
        currentTask = Task {
            await processMessage(text: text, conversationId: conversation.id, generation: generation)
        }
    }

    private func processMessage(text: String, conversationId: String, generation: Int) async {
        log.info("[\(generation)] processMessage START")

        // Heartbeat: logs every second while processing to detect MainActor stalls
        let heartbeat = Task { @MainActor in
            var tick = 0
            while !Task.isCancelled {
                tick += 1
                log.info("[\(generation)] ♥ MainActor alive \(tick)s")
                try? await Task.sleep(for: .seconds(1))
            }
        }

        defer {
            heartbeat.cancel()
            // Only clean up if this is still the active task —
            // prevents a cancelled task from wiping state set by a newer send().
            if taskGeneration == generation {
                log.info("[\(generation)] defer CLEANUP")
                isProcessing = false
                thinkingSteps = []
                currentPipelineName = nil
                expectedStageCount = 0
                currentStreamingStageName = nil
                currentStreamingContent = ""
                streamingAnswerContent = ""
                currentTask = nil
                resolvedPipelineKind = nil
            } else {
                log.info("[\(generation)] defer SKIP (gen mismatch)")
            }
        }

        do {
            log.info("[\(generation)] creating provider")
            let modelProvider = FoundationModelProvider()
            let detectedLanguage = AppLanguage.detect(from: text)
            let context = PipelineContext(
                modelProvider: modelProvider,
                language: detectedLanguage,
                longTermMemory: longTermMemory
            )

            log.info("[\(generation)] searching memory")
            let memoryHits = (try? await longTermMemory.search(
                query: MemorySearchQuery(text: text, limit: 3)
            )) ?? []
            await context.setRetrievedMemory(memoryHits)

            // Inject recent conversation history for multi-turn context
            if let conv = conversations.first(where: { $0.id == conversationId }) {
                let recentMessages = conv.messages.suffix(6) // Last 3 exchanges
                let history = recentMessages.map { msg in
                    (role: msg.role == .user ? "User" : "Assistant",
                     content: msg.content)
                }
                await context.setConversationHistory(history)
            }

            log.info("[\(generation)] creating stream")
            let (stream, continuation) = AsyncStream<PipelineEvent>.makeStream()
            await context.setEventContinuation(continuation)

            let searchDepth = webSearchEnabled && deepSearchEnabled ? 3 : 1
            let config = PipelineConfiguration(
                webSearchEnabled: webSearchEnabled,
                webSearchContextBudget: searchDepth > 1 ? 3000 : 2000,
                maxSearchDepth: searchDepth
            )

            let effectiveKind: PipelineKind
            if selectedPipelineKind == .auto {
                effectiveKind = await PipelineClassifier.classify(
                    query: text,
                    using: modelProvider
                )
                resolvedPipelineKind = effectiveKind
                await context.emit(.autoClassified(resolvedKind: effectiveKind))
            } else {
                effectiveKind = selectedPipelineKind
            }

            let pipeline = PipelineFactory.create(
                kind: effectiveKind,
                configuration: config
            )

            log.info("[\(generation)] launching pipeline (\(effectiveKind.rawValue))")
            let resultTask = Task.detached { () -> PipelineResult in
                do {
                    let result = try await pipeline.execute(query: text, context: context)
                    await context.finishEventStream()
                    return result
                } catch {
                    await context.finishEventStream()
                    throw error
                }
            }

            // ── Consume events OFF MainActor ──
            // The loop runs on the cooperative pool.  Each event hops to
            // MainActor individually, so the main thread is never held
            // for longer than a single handlePipelineEvent call.
            log.info("[\(generation)] consuming events (nonisolated)")
            await consumeEventStream(stream)
            log.info("[\(generation)] events done")

            // If cancelled (user sent a new message), stop the background pipeline too
            guard !Task.isCancelled else {
                log.info("[\(generation)] cancelled")
                resultTask.cancel()
                return
            }

            log.info("[\(generation)] awaiting result")
            let result = try await resultTask.value
            log.info("[\(generation)] got result")

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
            persistConversations()

            if result.finalOutput.confidence >= 0.3 {
                let entry = MemoryEntry(
                    kind: .summary,
                    content: result.finalOutput.content,
                    tags: ["auto-save", (resolvedPipelineKind ?? selectedPipelineKind).rawValue],
                    source: "pipeline:\(pipeline.name)"
                )
                try? await longTermMemory.save(entry)
            }

            log.info("[\(generation)] processMessage END")

        } catch {
            // Don't display cancellation as an error
            guard !Task.isCancelled else {
                log.info("[\(generation)] cancelled in catch")
                return
            }
            log.error("[\(generation)] ERROR: \(error)")
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

    // MARK: - Off-MainActor Event Consumption

    /// Consumes the pipeline event stream on the cooperative thread pool.
    /// Each event is dispatched to MainActor individually via
    /// `await self.handlePipelineEvent(event)`, so the main thread is
    /// never monopolised by the iteration loop itself.
    nonisolated private func consumeEventStream(_ stream: AsyncStream<PipelineEvent>) async {
        var count = 0
        for await event in stream {
            count += 1
            await self.handlePipelineEvent(event)
        }
        log.info("consumeEventStream finished after \(count) events")
    }

    // MARK: - Event Handling

    private func handlePipelineEvent(_ event: PipelineEvent) {
        switch event {
        case .pipelineStarted(let name, let count):
            log.info("  event pipelineStarted(\(name), stages=\(count))")
            currentPipelineName = name
            expectedStageCount = count

        case .stageStarted(let name, let kind, let index):
            log.info("  event stageStarted(\(name))")
            let step = ThinkingStep(stageName: name, stageKind: kind, index: index)
            thinkingSteps.append(step)
            currentStreamingStageName = name
            currentStreamingContent = ""

        case .stageStreamingContent(let name, let content):
            if isFinalAnswerStage(name) {
                streamingAnswerContent = content
            } else {
                currentStreamingStageName = name
                currentStreamingContent = content
            }

        case .stageCompleted(let name, let kind, let output, _):
            log.info("  event stageCompleted(\(name))")
            if let idx = thinkingSteps.lastIndex(where: { $0.stageName == name && $0.output == nil }) {
                thinkingSteps[idx].status = .completed
                thinkingSteps[idx].output = output
                thinkingSteps[idx].streamingContent = ""
                // Show search result status in step name
                if kind == .webSearch, let decision = output.metadata["searchDecision"] {
                    switch decision {
                    case "searched":
                        let count = output.metadata["resultCount"] ?? "0"
                        let pages = output.metadata["pagesFetched"] ?? "0"
                        let rounds = output.metadata["searchRounds"] ?? "1"
                        let label: String
                        if rounds != "1" {
                            label = "Deep Search (\(count) results, \(pages) pages, \(rounds) rounds)"
                        } else {
                            label = pages != "0" ? "Web Search (\(count) results, \(pages) pages)" : "Web Search (\(count) results)"
                        }
                        thinkingSteps[idx] = ThinkingStep(stageName: label, stageKind: .webSearch, index: thinkingSteps[idx].index)
                        thinkingSteps[idx].status = .completed
                        thinkingSteps[idx].output = output
                    case "failed":
                        thinkingSteps[idx] = ThinkingStep(stageName: "Web Search (offline)", stageKind: .webSearch, index: thinkingSteps[idx].index)
                        thinkingSteps[idx].status = .completed
                        thinkingSteps[idx].output = output
                    default:
                        break
                    }
                }
            }
            if currentStreamingStageName == name {
                currentStreamingContent = ""
            }

        case .stageFailed(let name, let error):
            log.error("  event stageFailed(\(name)): \(error)")
            if let idx = thinkingSteps.lastIndex(where: { $0.stageName == name }) {
                thinkingSteps[idx].status = .failed(error)
            }

        case .stageRetrying(let name, let attempt):
            if let idx = thinkingSteps.lastIndex(where: { $0.stageName == name }) {
                thinkingSteps[idx].status = .retrying(attempt: attempt)
            }

        case .webSearchStarted(let keywords):
            // Step already created by stageStarted — just update streaming content
            currentStreamingStageName = "WebSearch"
            currentStreamingContent = "Searching: \(keywords)"

        case .webSearchCompleted:
            // stageCompleted will handle marking the step as completed
            break

        case .webSearchSkipped:
            // Rename the existing step to indicate it was skipped
            if let idx = thinkingSteps.lastIndex(where: { $0.stageName == "WebSearch" }) {
                thinkingSteps[idx] = ThinkingStep(
                    stageName: "Web Search (skipped)",
                    stageKind: .webSearch,
                    index: thinkingSteps[idx].index
                )
            }

        case .deepSearchRoundStarted(let round, let keywords):
            currentStreamingContent = "Deep search (round \(round)): \(keywords)"

        case .webPageFetchStarted(let count):
            currentStreamingContent = "Fetching \(count) pages..."

        case .webPageFetchCompleted(let successCount):
            currentStreamingContent = "Fetched \(successCount) pages"

        case .webContentExtracting:
            currentStreamingContent = "Extracting key information..."

        case .autoClassified(let resolvedKind):
            resolvedPipelineKind = resolvedKind
            currentPipelineName = "Auto → \(resolvedKind.displayName)"

        case .pipelineCompleted, .pipelineFailed:
            break
        }
    }

    private func isFinalAnswerStage(_ name: String) -> Bool {
        ["Finalize", "Direct", "Explain", "Verify"].contains(name)
    }
}
