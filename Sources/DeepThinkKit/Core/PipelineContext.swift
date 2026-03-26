import Foundation
import NaturalLanguage

// MARK: - App Language

public enum AppLanguage: String, Codable, Sendable, CaseIterable, Identifiable {
    case english
    case japanese
    case chinese
    case korean
    case spanish
    case french
    case german
    case portuguese
    case russian
    case arabic
    case italian
    case hindi

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .english: "English"
        case .japanese: "日本語"
        case .chinese: "中文"
        case .korean: "한국어"
        case .spanish: "Español"
        case .french: "Français"
        case .german: "Deutsch"
        case .portuguese: "Português"
        case .russian: "Русский"
        case .arabic: "العربية"
        case .italian: "Italiano"
        case .hindi: "हिन्दी"
        }
    }

    /// Directive appended to system prompts to enforce response language.
    public var languageDirective: String {
        switch self {
        case .english: "You must respond in English."
        case .japanese: "日本語で回答してください。"
        case .chinese: "请用中文回答。"
        case .korean: "한국어로 답변해 주세요."
        case .spanish: "Responde en español."
        case .french: "Réponds en français."
        case .german: "Antworte auf Deutsch."
        case .portuguese: "Responda em português."
        case .russian: "Отвечай на русском языке."
        case .arabic: "أجب باللغة العربية."
        case .italian: "Rispondi in italiano."
        case .hindi: "हिंदी में उत्तर दें।"
        }
    }

    /// Detect language from input text using NaturalLanguage framework.
    public static func detect(from text: String) -> AppLanguage {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage else { return .english }
        switch dominant {
        case .japanese: return .japanese
        case .simplifiedChinese, .traditionalChinese: return .chinese
        case .korean: return .korean
        case .spanish: return .spanish
        case .french: return .french
        case .german: return .german
        case .portuguese: return .portuguese
        case .russian: return .russian
        case .arabic: return .arabic
        case .italian: return .italian
        case .hindi: return .hindi
        default: return .english
        }
    }
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
    private var retrievedMemory: [MemoryEntry] = []
    private var _webSearchResults: [WebSearchResult] = []
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

    public func setRetrievedMemory(_ entries: [MemoryEntry]) {
        retrievedMemory = entries
    }

    public func getRetrievedMemory() -> [MemoryEntry] {
        retrievedMemory
    }

    public func setWebSearchResults(_ results: [WebSearchResult]) {
        _webSearchResults = results
    }

    public func getWebSearchResults() -> [WebSearchResult] {
        _webSearchResults
    }

    // MARK: - Event Streaming

    public func setEventContinuation(_ continuation: AsyncStream<PipelineEvent>.Continuation) {
        self.eventContinuation = continuation
    }

    public func emit(_ event: PipelineEvent) {
        PipelineLogger.log(event)
        eventContinuation?.yield(event)
    }

    public func finishEventStream() {
        eventContinuation?.finish()
        eventContinuation = nil
    }

    // MARK: - Input Building

    public func buildInput(query: String, memoryContext: [MemoryEntry]? = nil) -> StageInput {
        StageInput(
            query: query,
            previousOutputs: stageOutputs,
            memoryContext: memoryContext ?? retrievedMemory,
            metadata: ["executionId": executionId]
        )
    }
}
