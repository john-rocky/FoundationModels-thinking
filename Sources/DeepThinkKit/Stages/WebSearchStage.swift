import Foundation

// MARK: - Web Search Stage

public struct WebSearchStage: Stage {
    public let kind: StageKind = .webSearch
    public let name = "WebSearch"
    public let purpose = "Autonomously decide if web search is needed and retrieve relevant information"
    public let maxRetries: Int = 1

    private let searchProvider: any WebSearchProvider
    private let maxResults: Int

    public init(
        searchProvider: any WebSearchProvider = DuckDuckGoSearchProvider(),
        maxResults: Int = 5
    ) {
        self.searchProvider = searchProvider
        self.maxResults = maxResults
    }

    public func execute(input: StageInput, context: PipelineContext) async throws -> StageOutput {
        await context.traceCollector.record(
            event: .stageStarted(stage: name, kind: kind, input: input.query)
        )

        // Step 1: Extract search keywords from query via LLM
        let keywords = try await extractKeywords(query: input.query, context: context)

        guard !keywords.isEmpty else {
            let reason = "Could not extract search keywords"
            await context.emit(.webSearchSkipped(reason: reason))

            let output = StageOutput(
                stageKind: .webSearch,
                content: "Web search skipped: \(reason)",
                confidence: 0.8,
                metadata: ["searchDecision": "skipped", "reason": reason]
            )
            await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
            return output
        }

        // Step 2: Execute web search
        await context.emit(.webSearchStarted(keywords: keywords))
        await context.emit(.stageStreamingContent(
            stageName: name,
            content: "Searching: \(keywords)"
        ))

        let results: [WebSearchResult]
        do {
            results = try await searchProvider.search(keywords: keywords, maxResults: maxResults)
        } catch {
            let output = StageOutput(
                stageKind: .webSearch,
                content: "Web search failed. Generating answer offline.",
                confidence: 0.3,
                metadata: ["searchDecision": "failed", "error": "\(error)"]
            )
            await context.emit(.webSearchCompleted(resultCount: 0))
            await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
            return output
        }

        // Step 3: Store results in context
        await context.setWebSearchResults(results)
        await context.emit(.webSearchCompleted(resultCount: results.count))

        // Step 4: Format results as stage output
        let formattedResults = formatSearchResults(results)

        await context.emit(.stageStreamingContent(stageName: name, content: formattedResults))

        let output = StageOutput(
            stageKind: .webSearch,
            content: formattedResults,
            bulletPoints: results.map { "[\($0.title)] \(String($0.snippet.prefix(80)))" },
            confidence: results.isEmpty ? 0.3 : 0.8,
            metadata: [
                "searchDecision": "searched",
                "searchQuery": keywords,
                "resultCount": "\(results.count)"
            ]
        )

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
        await context.workingMemory.store(output: output, for: name)

        return output
    }

    // MARK: - Keyword Extraction

    private func extractKeywords(query: String, context: PipelineContext) async throws -> String {
        let systemPrompt = """
            Extract 3-5 search keywords from the question for a web search.
            Output only the keywords on a single line. No explanation needed.
            """

        let raw = try await context.modelProvider.generate(
            systemPrompt: systemPrompt,
            userPrompt: truncate(query, to: 500)
        )

        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    // MARK: - Formatting

    private func formatSearchResults(_ results: [WebSearchResult]) -> String {
        guard !results.isEmpty else {
            return "No search results found."
        }
        let header = "[Web Search Results]"
        let items = results.enumerated().map { idx, result in
            "[\(idx + 1)] \(result.title)\n\(result.snippet)\nURL: \(result.url)"
        }.joined(separator: "\n\n")
        return "\(header)\n\n\(items)"
    }
}

// MARK: - Pipeline Integration Helper

/// Executes WebSearchStage if enabled in configuration. Returns output or nil.
public func executeWebSearchIfEnabled(
    query: String,
    context: PipelineContext,
    configuration: PipelineConfiguration,
    allOutputs: inout [StageOutput],
    stageIndex: inout Int
) async throws -> StageOutput? {
    guard configuration.webSearchEnabled else { return nil }

    let stage = WebSearchStage(maxResults: configuration.maxSearchResults)
    await context.emit(.stageStarted(stageName: stage.name, stageKind: .webSearch, index: stageIndex))

    let input = await context.buildInput(query: query)
    let output = try await executeWithRetry(stage: stage, input: input, context: context)

    allOutputs.append(output)
    await context.setOutput(output, for: "WebSearch")
    await context.emit(.stageCompleted(stageName: stage.name, stageKind: .webSearch, output: output, index: stageIndex))
    stageIndex += 1

    return output
}
