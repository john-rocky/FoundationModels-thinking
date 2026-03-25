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

        // Step 1: Ask LLM if search is needed
        let decision = try await decideSearch(query: input.query, context: context)

        guard decision.shouldSearch, !decision.keywords.isEmpty else {
            await context.emit(.webSearchSkipped(reason: decision.reason))

            let output = StageOutput(
                stageKind: .webSearch,
                content: context.language.isJapanese
                    ? "Web search not needed: \(decision.reason)"
                    : "Web search not needed: \(decision.reason)",
                confidence: 0.8,
                metadata: ["searchDecision": "skipped", "reason": decision.reason]
            )
            await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
            return output
        }

        // Step 2: Execute web search
        await context.emit(.webSearchStarted(keywords: decision.keywords))
        await context.emit(.stageStreamingContent(
            stageName: name,
            content: context.language.isJapanese
                ? "Searching: \(decision.keywords)"
                : "Searching: \(decision.keywords)"
        ))

        let results: [WebSearchResult]
        do {
            results = try await searchProvider.search(keywords: decision.keywords, maxResults: maxResults)
        } catch {
            let output = StageOutput(
                stageKind: .webSearch,
                content: context.language.isJapanese
                    ? "Web search failed. Generating answer offline."
                    : "Web search failed. Generating answer offline.",
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
        let formattedResults = formatSearchResults(results, language: context.language)

        await context.emit(.stageStreamingContent(stageName: name, content: formattedResults))

        let output = StageOutput(
            stageKind: .webSearch,
            content: formattedResults,
            bulletPoints: results.map { "[\($0.title)] \(String($0.snippet.prefix(80)))" },
            confidence: results.isEmpty ? 0.3 : 0.8,
            metadata: [
                "searchDecision": "searched",
                "searchQuery": decision.keywords,
                "resultCount": "\(results.count)"
            ]
        )

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
        await context.workingMemory.store(output: output, for: name)

        return output
    }

    // MARK: - LLM Decision

    private func decideSearch(query: String, context: PipelineContext) async throws -> SearchDecision {
        let systemPrompt: String
        if context.language.isJapanese {
            systemPrompt = """
            ユーザーの質問にウェブ検索が有用か判断してください。
            最新情報・具体的事実・統計・ニュース・製品情報が必要ならYES。
            一般知識・数学・論理・概念説明で十分ならNO。
            以下の形式で回答：
            SEARCH: YES or NO
            REASON: 理由1行
            KEYWORDS: 検索語3-5語（NOなら空）
            """
        } else {
            systemPrompt = """
            Decide if web search would help answer this question.
            YES if it needs current info, specific facts, statistics, news, or product details.
            NO if general knowledge, math, logic, or concepts suffice.
            Format:
            SEARCH: YES or NO
            REASON: one line
            KEYWORDS: 3-5 search terms (empty if NO)
            """
        }

        let raw = try await context.modelProvider.generate(
            systemPrompt: systemPrompt,
            userPrompt: truncate(query, to: 500)
        )

        return parseSearchDecision(raw)
    }

    private func parseSearchDecision(_ raw: String) -> SearchDecision {
        let lines = raw.components(separatedBy: .newlines)
        var shouldSearch = false
        var reason = ""
        var keywords = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let upper = trimmed.uppercased()
            if upper.hasPrefix("SEARCH:") {
                let value = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces).uppercased()
                shouldSearch = value.hasPrefix("YES")
            } else if upper.hasPrefix("REASON:") {
                reason = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            } else if upper.hasPrefix("KEYWORDS:") {
                keywords = String(trimmed.dropFirst(9)).trimmingCharacters(in: .whitespaces)
            }
        }

        return SearchDecision(shouldSearch: shouldSearch, reason: reason, keywords: keywords)
    }

    // MARK: - Formatting

    private func formatSearchResults(_ results: [WebSearchResult], language: AppLanguage) -> String {
        guard !results.isEmpty else {
            return language.isJapanese ? "No search results found." : "No search results found."
        }
        let header = language.isJapanese ? "[Web Search Results]" : "[Web Search Results]"
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
