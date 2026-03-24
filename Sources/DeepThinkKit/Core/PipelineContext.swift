import Foundation

// MARK: - App Language

public enum AppLanguage: String, Codable, Sendable, CaseIterable, Identifiable {
    case english
    case japanese

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .english: "English"
        case .japanese: "Japanese"
        }
    }

    public var isJapanese: Bool { self == .japanese }
}

// MARK: - Pipeline Context

public actor PipelineContext {
    public nonisolated let executionId: String
    public nonisolated let sessionMemory: SessionMemory
    public nonisolated let workingMemory: WorkingMemory
    public nonisolated let longTermMemory: LongTermMemory
    public nonisolated let traceCollector: TraceCollector
    public nonisolated let modelProvider: any ModelProvider
    public nonisolated let language: AppLanguage

    private var stageOutputs: [String: StageOutput] = [:]
    private var eventContinuation: AsyncStream<PipelineEvent>.Continuation?

    public init(
        executionId: String = UUID().uuidString,
        modelProvider: any ModelProvider,
        language: AppLanguage = .japanese,
        sessionMemory: SessionMemory? = nil,
        workingMemory: WorkingMemory? = nil,
        longTermMemory: LongTermMemory? = nil,
        traceCollector: TraceCollector? = nil
    ) {
        self.executionId = executionId
        self.modelProvider = modelProvider
        self.language = language
        self.sessionMemory = sessionMemory ?? SessionMemory()
        self.workingMemory = workingMemory ?? WorkingMemory()
        self.longTermMemory = longTermMemory ?? LongTermMemory()
        self.traceCollector = traceCollector ?? TraceCollector()
    }

    public func setOutput(_ output: StageOutput, for stageId: String) {
        stageOutputs[stageId] = output
    }

    public func getOutput(for stageId: String) -> StageOutput? {
        stageOutputs[stageId]
    }

    public func allOutputs() -> [String: StageOutput] {
        stageOutputs
    }

    // MARK: - Event Streaming

    public func setEventContinuation(_ continuation: AsyncStream<PipelineEvent>.Continuation) {
        self.eventContinuation = continuation
    }

    public func emit(_ event: PipelineEvent) {
        eventContinuation?.yield(event)
    }

    public func finishEventStream() {
        eventContinuation?.finish()
        eventContinuation = nil
    }

    // MARK: - Input Building

    public func buildInput(query: String, memoryContext: [MemoryEntry] = []) -> StageInput {
        StageInput(
            query: query,
            previousOutputs: stageOutputs,
            memoryContext: memoryContext,
            metadata: ["executionId": executionId]
        )
    }
}
