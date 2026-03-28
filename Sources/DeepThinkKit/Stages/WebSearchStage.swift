import Foundation

// MARK: - Web Search Stage

public struct WebSearchStage: Stage {
    public let kind: StageKind = .webSearch
    public let name = "WebSearch"
    public let purpose = "Autonomously decide if web search is needed and retrieve relevant information"
    public let maxRetries: Int = 1

    private let searchProvider: any WebSearchProvider
    private let maxResults: Int
    private let pageFetcher: WebPageFetcher
    private let maxPageFetchCount: Int

    public init(
        searchProvider: any WebSearchProvider = DuckDuckGoSearchProvider(),
        maxResults: Int = 5,
        maxPageFetchCount: Int = 2
    ) {
        self.searchProvider = searchProvider
        self.maxResults = maxResults
        self.pageFetcher = WebPageFetcher()
        self.maxPageFetchCount = maxPageFetchCount
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

        guard !results.isEmpty else {
            let output = StageOutput(
                stageKind: .webSearch,
                content: "No search results found.",
                confidence: 0.3,
                metadata: ["searchDecision": "searched", "searchQuery": keywords, "resultCount": "0"]
            )
            await context.emit(.webSearchCompleted(resultCount: 0))
            await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
            return output
        }

        await context.emit(.webSearchCompleted(resultCount: results.count))

        // Step 3: Fetch actual page content from top results (parallel, best-effort)
        let fetchCount = min(results.count, maxPageFetchCount)
        await context.emit(.webPageFetchStarted(count: fetchCount))
        await context.emit(.stageStreamingContent(
            stageName: name,
            content: "Fetching \(fetchCount) pages..."
        ))

        var enrichedResults = results
        let fetchedPages = await withTaskGroup(of: (Int, String).self) { group in
            for i in 0..<fetchCount {
                let url = results[i].url
                group.addTask {
                    let content = await pageFetcher.fetchPageContent(url: url)
                    return (i, content)
                }
            }
            var pages: [(Int, String)] = []
            for await result in group {
                pages.append(result)
            }
            return pages
        }

        var successCount = 0
        for (index, content) in fetchedPages {
            if !content.isEmpty {
                enrichedResults[index].pageContent = content
                successCount += 1
            }
        }
        await context.emit(.webPageFetchCompleted(successCount: successCount))

        // Step 4: Store results in context
        await context.setWebSearchResults(enrichedResults)

        // Step 5: Format results — page content directly enriches snippets (no extra LLM call)
        let formattedResults = formatSearchResults(enrichedResults)

        await context.emit(.stageStreamingContent(stageName: name, content: formattedResults))

        let output = StageOutput(
            stageKind: .webSearch,
            content: formattedResults,
            bulletPoints: enrichedResults.prefix(5).map { "[\($0.title)] \(String($0.snippet.prefix(80)))" },
            confidence: results.isEmpty ? 0.3 : 0.8,
            metadata: [
                "searchDecision": "searched",
                "searchQuery": keywords,
                "resultCount": "\(results.count)",
                "pagesFetched": "\(successCount)"
            ]
        )

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
        await context.workingMemory.store(output: output, for: name)

        return output
    }

    // MARK: - Keyword Extraction

    private func extractKeywords(query: String, context: PipelineContext) async throws -> String {
        // Try LLM extraction first
        let systemPrompt = """
            Extract 3-5 search keywords from the question for a web search.
            Output only the keywords on a single line. No explanation needed.
            """
        let raw = try await context.modelProvider.generate(
            systemPrompt: systemPrompt,
            userPrompt: truncate(query, to: 500)
        )
        let firstLine = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespaces) ?? ""

        // Validate: if LLM returned a sentence instead of keywords, fall back
        let looksLikeSentence = firstLine.count > 80
            || firstLine.lowercased().hasPrefix("here ")
            || firstLine.lowercased().hasPrefix("the ")
            || firstLine.lowercased().hasPrefix("based on")
            || firstLine.contains("keywords")
        if looksLikeSentence || firstLine.isEmpty {
            return heuristicKeywords(from: query)
        }
        return firstLine
    }

    /// Fallback: strip question patterns and use core text as search query.
    private func heuristicKeywords(from query: String) -> String {
        var q = query
        for p in ["について教えて", "とは何ですか", "とは", "って何", "を教えて",
                   "について", "ですか？", "ですか", "は？",
                   "what is ", "who is ", "tell me about ",
                   "?", "？", "。"] {
            q = q.replacingOccurrences(of: p, with: " ")
        }
        return q.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .prefix(100)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Formatting

    /// Format results: if page content was fetched, use it to enrich the snippet.
    /// No extra LLM call — the answering stage will interpret the richer content.
    private func formatSearchResults(_ results: [WebSearchResult]) -> String {
        guard !results.isEmpty else {
            return "No search results found."
        }
        let header = "[Web Search Results]"
        let items = results.enumerated().map { idx, result in
            var entry = "[\(idx + 1)] \(result.title)\n\(result.snippet)"
            // Append page excerpt if available (richer than snippet alone)
            if let page = result.pageContent, !page.isEmpty {
                entry += "\n\(page)"
            }
            entry += "\nURL: \(result.url)"
            return entry
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
