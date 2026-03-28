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
    private let maxSearchDepth: Int

    public init(
        searchProvider: any WebSearchProvider = DuckDuckGoSearchProvider(),
        maxResults: Int = 5,
        maxPageFetchCount: Int = 2,
        maxSearchDepth: Int = 1
    ) {
        self.searchProvider = searchProvider
        self.maxResults = maxResults
        self.pageFetcher = WebPageFetcher()
        self.maxPageFetchCount = maxPageFetchCount
        self.maxSearchDepth = maxSearchDepth
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

        // Step 2: Execute web search (round 1)
        await context.emit(.webSearchStarted(keywords: keywords))
        await context.emit(.stageStreamingContent(
            stageName: name,
            content: "Searching: \(keywords)"
        ))

        var allResults: [WebSearchResult]
        do {
            allResults = try await searchProvider.search(keywords: keywords, maxResults: maxResults)
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

        guard !allResults.isEmpty else {
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

        await context.emit(.webSearchCompleted(resultCount: allResults.count))
        var actualRounds = 1

        // Step 3: Deep search - evaluate results and do follow-up rounds if needed
        if maxSearchDepth > 1 {
            for round in 2...maxSearchDepth {
                guard let followUpQuery = try? await evaluateAndSuggestFollowUp(
                    query: input.query,
                    currentResults: allResults,
                    context: context
                ) else { break }

                actualRounds = round
                await context.emit(.deepSearchRoundStarted(round: round, keywords: followUpQuery))
                await context.emit(.stageStreamingContent(
                    stageName: name,
                    content: "Deep search (\(round)/\(maxSearchDepth)): \(followUpQuery)"
                ))

                let newResults: [WebSearchResult]
                do {
                    newResults = try await searchProvider.search(
                        keywords: followUpQuery,
                        maxResults: maxResults
                    )
                } catch {
                    break
                }

                // Merge results, deduplicating by URL
                let existingURLs = Set(allResults.map(\.url))
                let uniqueNew = newResults.filter { !existingURLs.contains($0.url) }
                allResults.append(contentsOf: uniqueNew)

                await context.emit(.webSearchCompleted(resultCount: allResults.count))
            }
        }

        // Step 4: Fetch actual page content from top results (parallel, best-effort)
        let fetchCount = min(allResults.count, maxPageFetchCount)
        await context.emit(.webPageFetchStarted(count: fetchCount))
        await context.emit(.stageStreamingContent(
            stageName: name,
            content: "Fetching \(fetchCount) pages..."
        ))

        var enrichedResults = allResults
        let fetchedPages = await withTaskGroup(of: (Int, String).self) { group in
            for i in 0..<fetchCount {
                let url = allResults[i].url
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

        // Step 5: Store results in context
        await context.setWebSearchResults(enrichedResults)

        // Step 6: Format results — page content directly enriches snippets (no extra LLM call)
        let formattedResults = formatSearchResults(enrichedResults)

        await context.emit(.stageStreamingContent(stageName: name, content: formattedResults))

        let output = StageOutput(
            stageKind: .webSearch,
            content: formattedResults,
            bulletPoints: enrichedResults.prefix(5).map { "[\($0.title)] \(String($0.snippet.prefix(80)))" },
            confidence: allResults.isEmpty ? 0.3 : 0.8,
            metadata: [
                "searchDecision": "searched",
                "searchQuery": keywords,
                "resultCount": "\(allResults.count)",
                "pagesFetched": "\(successCount)",
                "searchRounds": "\(actualRounds)"
            ]
        )

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
        await context.workingMemory.store(output: output, for: name)

        return output
    }

    // MARK: - Deep Search Evaluation

    private func evaluateAndSuggestFollowUp(
        query: String,
        currentResults: [WebSearchResult],
        context: PipelineContext
    ) async throws -> String? {
        let resultSummary = currentResults.prefix(5).enumerated().map { idx, r in
            "[\(idx + 1)] \(r.title): \(String(r.snippet.prefix(80)))"
        }.joined(separator: "\n")

        let systemPrompt = "You evaluate web search results. Respond with one line only."
        let userPrompt = """
            Question: \(truncate(query, to: 300))

            Search results:
            \(resultSummary)

            Are these results sufficient to answer the question?
            If YES, respond: SUFFICIENT
            If NO, respond with a better search query (keywords only, no explanation).
            """

        let response = try await context.modelProvider.generate(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )

        let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespaces) ?? ""

        if cleaned.uppercased().contains("SUFFICIENT") || cleaned.isEmpty {
            return nil
        }

        // Validate: should look like keywords, not a sentence
        let looksLikeSentence = cleaned.count > 80
            || cleaned.lowercased().hasPrefix("here ")
            || cleaned.lowercased().hasPrefix("the ")
            || cleaned.lowercased().hasPrefix("based on")
            || cleaned.lowercased().hasPrefix("yes")
            || cleaned.lowercased().hasPrefix("no,")
            || cleaned.contains("keywords")
        if looksLikeSentence {
            return nil
        }

        return cleaned
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

    let pageFetchCount = configuration.maxSearchDepth > 1 ? 3 : 2
    let stage = WebSearchStage(
        maxResults: configuration.maxSearchResults,
        maxPageFetchCount: pageFetchCount,
        maxSearchDepth: configuration.maxSearchDepth
    )
    await context.emit(.stageStarted(stageName: stage.name, stageKind: .webSearch, index: stageIndex))

    let input = await context.buildInput(query: query)
    let output = try await executeWithRetry(stage: stage, input: input, context: context)

    allOutputs.append(output)
    await context.setOutput(output, for: "WebSearch")
    await context.emit(.stageCompleted(stageName: stage.name, stageKind: .webSearch, output: output, index: stageIndex))
    stageIndex += 1

    return output
}
