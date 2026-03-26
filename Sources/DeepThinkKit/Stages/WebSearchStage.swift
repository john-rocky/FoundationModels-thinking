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

        // Step 1: Generate a search query from the user's question
        let searchQuery = try await generateSearchQuery(query: input.query, context: context)

        guard !searchQuery.isEmpty else {
            let reason = "Could not generate search query"
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
        await context.emit(.webSearchStarted(keywords: searchQuery))
        await context.emit(.stageStreamingContent(
            stageName: name,
            content: "Searching: \(searchQuery)"
        ))

        let results: [WebSearchResult]
        do {
            results = try await searchProvider.search(keywords: searchQuery, maxResults: maxResults)
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
                metadata: ["searchDecision": "searched", "searchQuery": searchQuery, "resultCount": "0"]
            )
            await context.emit(.webSearchCompleted(resultCount: 0))
            await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
            return output
        }

        await context.emit(.webSearchCompleted(resultCount: results.count))

        // Step 3: Fetch actual page content from top results
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

        // Step 4: Extract core information using LLM
        var coreInfo = ""
        if successCount > 0 {
            await context.emit(.webContentExtracting)
            await context.emit(.stageStreamingContent(
                stageName: name,
                content: "Extracting key information..."
            ))
            coreInfo = await extractCoreInformation(
                query: input.query,
                results: enrichedResults,
                context: context
            )
        }

        // Step 5: Store results in context
        await context.setWebSearchResults(enrichedResults)

        // Step 6: Format output
        let formattedResults = formatSearchResults(results: enrichedResults, coreInfo: coreInfo)

        await context.emit(.stageStreamingContent(stageName: name, content: formattedResults))

        let output = StageOutput(
            stageKind: .webSearch,
            content: formattedResults,
            bulletPoints: enrichedResults.prefix(5).map { "[\($0.title)] \(String($0.snippet.prefix(80)))" },
            confidence: 0.8,
            metadata: [
                "searchDecision": "searched",
                "searchQuery": searchQuery,
                "resultCount": "\(results.count)",
                "pagesFetched": "\(successCount)"
            ]
        )

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
        await context.workingMemory.store(output: output, for: name)

        return output
    }

    // MARK: - Search Query Generation

    private func generateSearchQuery(query: String, context: PipelineContext) async throws -> String {
        let systemPrompt = """
            Generate a short web search query (3-8 words) for the question below.
            Capture the core intent. Output only the query, nothing else.
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

    // MARK: - Core Information Extraction

    private func extractCoreInformation(
        query: String,
        results: [WebSearchResult],
        context: PipelineContext
    ) async -> String {
        let pagesWithContent = results.filter { $0.pageContent != nil && !$0.pageContent!.isEmpty }
        guard !pagesWithContent.isEmpty else { return "" }

        // Keep total page text small enough for on-device model context
        let perPageBudget = 600
        let pageTexts = pagesWithContent.prefix(2).enumerated().map { idx, result in
            let content = String(result.pageContent!.prefix(perPageBudget))
            return "[Page \(idx + 1): \(result.title)]\n\(content)"
        }.joined(separator: "\n\n")

        let systemPrompt = "Extract the key facts that answer the question from the web pages below. Be concise."

        let userPrompt = "Question: \(truncate(query, to: 200))\n\n\(pageTexts)"

        do {
            let extracted = try await context.modelProvider.generate(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt
            )
            let trimmed = extracted.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "" : trimmed
        } catch {
            // Fall back gracefully — return empty and let snippets be used
            return ""
        }
    }

    // MARK: - Formatting

    private func formatSearchResults(results: [WebSearchResult], coreInfo: String) -> String {
        guard !results.isEmpty else {
            return "No search results found."
        }

        if !coreInfo.isEmpty {
            // Core info available: show extracted facts + compact source list
            let sources = results.enumerated().map { idx, result in
                "[\(idx + 1)] \(result.title) - \(result.url)"
            }.joined(separator: "\n")
            return "[Web Search Results]\n\n\(coreInfo)\n\n[Sources]\n\(sources)"
        }

        // Fallback: show full snippets (same format as before enhancement)
        let items = results.enumerated().map { idx, result in
            "[\(idx + 1)] \(result.title)\n\(result.snippet)\nURL: \(result.url)"
        }.joined(separator: "\n\n")
        return "[Web Search Results]\n\n\(items)"
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
