import Foundation

// MARK: - Pipeline Event

/// Events emitted during pipeline execution for real-time UI streaming.
public enum PipelineEvent: Sendable {
    /// Pipeline execution has begun
    case pipelineStarted(pipelineName: String, stageCount: Int)

    /// A stage is about to begin execution
    case stageStarted(stageName: String, stageKind: StageKind, index: Int)

    /// Streaming partial content from a stage
    case stageStreamingContent(stageName: String, content: String)

    /// A stage completed successfully
    case stageCompleted(stageName: String, stageKind: StageKind, output: StageOutput, index: Int)

    /// A stage failed (may be retried)
    case stageFailed(stageName: String, error: String)

    /// A stage is being retried
    case stageRetrying(stageName: String, attempt: Int)

    /// Parallel branches started (for BranchMerge / SelfConsistency)
    case branchesStarted(branchNames: [String])

    /// A single branch within a parallel group completed
    case branchCompleted(branchName: String, output: StageOutput)

    /// Critique-revise loop iteration started
    case loopIterationStarted(iteration: Int, maxIterations: Int)

    /// Critique-revise loop ended
    case loopEnded(reason: String)

    /// Pipeline execution completed
    case pipelineCompleted(result: PipelineResult)

    /// Pipeline execution failed
    case pipelineFailed(error: String)

    /// Web search started with extracted keywords
    case webSearchStarted(keywords: String)

    /// Web search completed with results
    case webSearchCompleted(resultCount: Int)

    /// Web search skipped (LLM decided it's not needed)
    case webSearchSkipped(reason: String)

    /// Model used fallback path (instructions embedded in prompt instead of instructions: parameter)
    case modelFallbackUsed(stageName: String)
}

public typealias PipelineEventStream = AsyncStream<PipelineEvent>
