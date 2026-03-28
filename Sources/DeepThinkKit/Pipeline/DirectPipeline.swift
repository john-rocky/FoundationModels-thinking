import Foundation

// MARK: - Direct Pipeline (Single-Pass)
// Query -> Response (no multi-stage reasoning)

public struct DirectPipeline: Pipeline, Sendable {
    public let name = "Direct"
    public let description = "Query -> Response (single inference, no pipeline)"
    public let configuration: PipelineConfiguration

    public var stages: [any Stage] { [] }

    public init(configuration: PipelineConfiguration = .default) {
        self.configuration = configuration
    }

    public func execute(query: String, context: PipelineContext) async throws -> PipelineResult {
        let startTime = Date.now
        await context.traceCollector.setPipeline(
            name: name,
            executionId: context.executionId
        )
        await context.traceCollector.record(
            event: .pipelineStarted(name: name, query: query)
        )
        let searchStageCount = configuration.webSearchEnabled ? 1 : 0
        await context.emit(.pipelineStarted(pipelineName: name, stageCount: 1 + searchStageCount))

        // Optional: Web Search
        var webSearchContent = ""
        if configuration.webSearchEnabled {
            let pageFetchCount = configuration.maxSearchDepth > 1 ? 3 : 2
            let stage = WebSearchStage(
                maxResults: configuration.maxSearchResults,
                maxPageFetchCount: pageFetchCount,
                maxSearchDepth: configuration.maxSearchDepth
            )
            await context.emit(.stageStarted(stageName: stage.name, stageKind: .webSearch, index: 0))
            do {
                let input = await context.buildInput(query: query)
                let searchOutput = try await executeWithRetry(stage: stage, input: input, context: context)
                await context.setOutput(searchOutput, for: "WebSearch")
                await context.emit(.stageCompleted(stageName: stage.name, stageKind: .webSearch, output: searchOutput, index: 0))
                if searchOutput.metadata["searchDecision"] == "searched" {
                    webSearchContent = "\n\n\(truncate(searchOutput.content, to: configuration.webSearchContextBudget))"
                }
            } catch {
                await context.emit(.stageFailed(stageName: stage.name, error: "\(error)"))
            }
        }

        let directIndex = searchStageCount
        await context.traceCollector.record(
            event: .stageStarted(stage: "Direct", kind: .solve, input: query)
        )
        await context.emit(.stageStarted(stageName: "Direct", stageKind: .solve, index: directIndex))

        let raw: String
        do {
            let memory = await context.getRetrievedMemory()
            let history = await context.getConversationHistory()
            var userPrompt = query
            if !history.isEmpty {
                userPrompt += formatConversationHistory(history)
            }
            if !memory.isEmpty {
                userPrompt += formatMemoryContext(memory)
            }
            userPrompt += webSearchContent
            if configuration.webSearchEnabled && webSearchContent.isEmpty {
                userPrompt += "\n\nNote: A web search was performed but found no relevant information. If you don't have reliable information about this topic, say so honestly."
            }
            let directSystemPrompt = localizedSystemPrompt(
                "You are a friendly, helpful assistant. Be conversational and natural. Give thorough but concise answers. If you are unsure or don't have enough information, say so honestly instead of guessing.",
                language: context.language
            )
            do {
                raw = try await streamingGenerate(
                    stageName: "Direct",
                    systemPrompt: directSystemPrompt,
                    userPrompt: userPrompt,
                    context: context
                )
            } catch let error as ModelError where error.isContextTooLong && !memory.isEmpty {
                // Retry without memory context (keep web search results)
                raw = try await streamingGenerate(
                    stageName: "Direct",
                    systemPrompt: directSystemPrompt,
                    userPrompt: query + webSearchContent,
                    context: context
                )
            }
        } catch {
            let stageError: Error
            if case ModelError.safetyFilterViolation = error {
                stageError = StageError.contentFiltered(stage: "Direct")
            } else if case ModelError.contextTooLong = error {
                stageError = StageError.contextTooLong(stage: "Direct")
            } else {
                stageError = error
            }
            await context.emit(.stageFailed(stageName: "Direct", error: "\(stageError)"))
            await context.emit(.pipelineFailed(error: "\(stageError)"))
            await context.finishEventStream()
            throw stageError
        }

        let output = parseOutput(raw: raw, kind: .solve)

        await context.traceCollector.record(
            event: .stageCompleted(stage: "Direct", output: output)
        )
        await context.emit(.stageCompleted(stageName: "Direct", stageKind: .solve, output: output, index: directIndex))

        let endTime = Date.now
        let trace = await context.traceCollector.allRecords()

        await context.traceCollector.record(
            event: .pipelineCompleted(
                name: name,
                duration: endTime.timeIntervalSince(startTime)
            )
        )

        let result = PipelineResult(
            pipelineName: name,
            query: query,
            finalOutput: output,
            stageOutputs: [output],
            trace: trace,
            startTime: startTime,
            endTime: endTime
        )

        await context.emit(.pipelineCompleted(result: result))
        await context.finishEventStream()

        return result
    }
}
