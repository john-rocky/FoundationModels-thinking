import Foundation

// MARK: - Stage Protocol

public protocol Stage: Sendable {
    var id: String { get }
    var kind: StageKind { get }
    var name: String { get }
    var purpose: String { get }
    var maxRetries: Int { get }

    func execute(input: StageInput, context: PipelineContext) async throws -> StageOutput
}

extension Stage {
    public var id: String { name }
    public var maxRetries: Int { 2 }
}

// MARK: - Stage Execution with Retry

public func executeWithRetry(
    stage: some Stage,
    input: StageInput,
    context: PipelineContext
) async throws -> StageOutput {
    var lastError: Error?
    var currentInput = input

    for attempt in 1...max(1, stage.maxRetries) {
        do {
            let output = try await stage.execute(input: currentInput, context: context)
            return output
        } catch {
            if let modelError = error as? ModelError {
                switch modelError {
                case .safetyFilterViolation:
                    if attempt < stage.maxRetries {
                        lastError = error
                        await context.traceCollector.record(
                            event: .retry(stage: stage.name, attempt: attempt, error: error)
                        )
                        await context.emit(.stageRetrying(stageName: stage.name, attempt: attempt))
                        try await Task.sleep(for: .milliseconds(200 * attempt))
                        continue
                    }
                    throw StageError.contentFiltered(stage: stage.name)
                case .contextTooLong:
                    // Retry without memory context to shorten the prompt
                    if !currentInput.memoryContext.isEmpty {
                        currentInput = StageInput(
                            query: currentInput.query,
                            previousOutputs: currentInput.previousOutputs,
                            memoryContext: [],
                            metadata: currentInput.metadata
                        )
                        await context.traceCollector.record(
                            event: .retry(stage: stage.name, attempt: attempt, error: error)
                        )
                        await context.emit(.stageRetrying(stageName: stage.name, attempt: attempt))
                        continue
                    }
                    throw StageError.contextTooLong(stage: stage.name)
                case .modelUnavailable:
                    throw StageError.modelUnavailable
                default:
                    break
                }
            }
            lastError = error
            await context.traceCollector.record(
                event: .retry(stage: stage.name, attempt: attempt, error: error)
            )
            await context.emit(.stageRetrying(stageName: stage.name, attempt: attempt))
            if attempt < stage.maxRetries {
                try await Task.sleep(for: .milliseconds(100 * attempt))
            }
        }
    }
    throw StageError.maxRetriesExceeded(stage: stage.name, attempts: stage.maxRetries, lastError: lastError)
}
