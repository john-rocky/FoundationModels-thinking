import Foundation

// MARK: - Pipeline Event

/// Events emitted during pipeline execution for real-time UI streaming.
public enum PipelineEvent: Sendable {
    case pipelineStarted(pipelineName: String, stageCount: Int)
    case stageStarted(stageName: String, stageKind: StageKind, index: Int)
    case stageStreamingContent(stageName: String, content: String)
    case stageCompleted(stageName: String, stageKind: StageKind, output: StageOutput, index: Int)
    case stageFailed(stageName: String, error: String)
    case stageRetrying(stageName: String, attempt: Int)
    case pipelineCompleted(result: PipelineResult)
    case pipelineFailed(error: String)

    // Web search events
    case webSearchStarted(keywords: String)
    case webSearchCompleted(resultCount: Int)
    case webSearchSkipped(reason: String)
    case webPageFetchStarted(count: Int)
    case webPageFetchCompleted(successCount: Int)
    case webContentExtracting
    case deepSearchRoundStarted(round: Int, keywords: String)

    // Auto mode classification
    case autoClassified(resolvedKind: PipelineKind)
}

public typealias PipelineEventStream = AsyncStream<PipelineEvent>
