import Foundation

// MARK: - Context Size Limits

private let maxContextLength = 1200
private let maxPreviousOutputLength = 800

// MARK: - Streaming Generate Helper

/// Streams generation from the model provider and emits partial content events.
/// Returns the final accumulated text.
func streamingGenerate(
    stageName: String,
    systemPrompt: String?,
    userPrompt: String,
    context: PipelineContext
) async throws -> String {
    var finalContent = ""
    let stream = context.modelProvider.generateStream(
        systemPrompt: systemPrompt,
        userPrompt: userPrompt
    )
    for try await partial in stream {
        finalContent = partial
        await context.emit(.stageStreamingContent(stageName: stageName, content: partial))
    }
    return finalContent
}

// MARK: - Streaming Session Generate Helper

/// Streams generation from an existing multi-turn ModelSession and emits partial content events.
/// Returns the final accumulated text.
func streamingSessionGenerate(
    stageName: String,
    prompt: String,
    session: any ModelSession,
    context: PipelineContext
) async throws -> String {
    var finalContent = ""
    let stream = try await session.streamResponse(to: prompt)
    for try await partial in stream {
        finalContent = partial
        await context.emit(.stageStreamingContent(stageName: stageName, content: partial))
    }
    return finalContent
}

// MARK: - Stage Output Parser

func parseOutput(raw: String, kind: StageKind) -> StageOutput {
    let content = raw.trimmingCharacters(in: .whitespacesAndNewlines)

    let bulletPoints = extractBulletPoints(from: content)
    let confidence = extractConfidence(from: content)
    let unresolvedIssues = extractSection(from: content, headers: [
        "未解決事項", "残存課題", "未確定点", "不明点",
        "Unresolved Issues", "Open Issues", "Remaining Issues", "Unknowns"
    ])
    let assumptions = extractSection(from: content, headers: [
        "前提条件", "前提",
        "Assumptions", "Prerequisites"
    ])

    return StageOutput(
        stageKind: kind,
        content: content,
        bulletPoints: bulletPoints,
        confidence: confidence,
        unresolvedIssues: unresolvedIssues,
        assumptions: assumptions
    )
}

/// Wrap a base system prompt with the language directive from context.
func localizedSystemPrompt(_ base: String, language: AppLanguage) -> String {
    "\(base)\n\(language.languageDirective)"
}

private let markdownDirective = "Format your response with Markdown: use headings (##), bold (**), and bullet lists where appropriate."

/// Wrap a base system prompt with markdown formatting and the language directive.
/// Use for stages whose output is displayed directly to the user.
func localizedFinalAnswerSystemPrompt(_ base: String, language: AppLanguage) -> String {
    "\(base)\n\(markdownDirective)\n\(language.languageDirective)"
}

func formatMemoryContext(_ entries: [MemoryEntry]) -> String {
    guard !entries.isEmpty else { return "" }
    let formatted = entries.prefix(2).map { entry in
        "- [\(entry.kind.rawValue)] \(truncate(entry.content, to: 100))"
    }.joined(separator: "\n")
    return "\n\n[Reference Memory]\n\(formatted)"
}

/// Truncate text to a maximum character count, preserving word boundaries
func truncate(_ text: String, to maxLength: Int = maxPreviousOutputLength) -> String {
    guard text.count > maxLength else { return text }
    let truncated = text.prefix(maxLength)
    if let lastBreak = truncated.lastIndex(where: { $0 == "\n" || $0 == "。" || $0 == "." }) {
        return String(truncated[truncated.startIndex...lastBreak])
    }
    return String(truncated) + "..."
}

/// Extract the most important content from a previous stage output (bullet points preferred)
func summarizeForNextStage(_ output: StageOutput) -> String {
    if !output.bulletPoints.isEmpty {
        let points = output.bulletPoints.prefix(8).map { "- \($0)" }.joined(separator: "\n")
        return truncate(points, to: maxPreviousOutputLength)
    }
    return truncate(output.content, to: maxPreviousOutputLength)
}

// MARK: - Private Helpers

private func extractBulletPoints(from text: String) -> [String] {
    text.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { $0.hasPrefix("- ") || $0.hasPrefix("* ") }
        .map { String($0.dropFirst(2)) }
}

private func extractConfidence(from text: String) -> Double {
    let lines = text.components(separatedBy: .newlines)
    for (index, line) in lines.enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.contains("確信度") || trimmed.contains("confidence") {
            if let value = extractNumber(from: trimmed) {
                return value
            }
            if index + 1 < lines.count {
                let nextLine = lines[index + 1].trimmingCharacters(in: .whitespaces)
                if let value = extractNumber(from: nextLine) {
                    return value
                }
            }
        }
    }
    return 0.5
}

private func extractNumber(from text: String) -> Double? {
    let pattern = #"(0?\.\d+|1\.0|0|1)"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let range = Range(match.range(at: 1), in: text) else {
        return nil
    }
    return Double(text[range])
}

private func extractSection(from text: String, headers: [String]) -> [String] {
    let lines = text.components(separatedBy: .newlines)
    var inSection = false
    var results: [String] = []

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()

        if trimmed.hasPrefix("##") || trimmed.hasPrefix("**") {
            inSection = headers.contains(where: { lower.contains($0.lowercased()) })
            continue
        }

        if inSection {
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                results.append(String(trimmed.dropFirst(2)))
            } else if trimmed.isEmpty {
                continue
            } else if trimmed.hasPrefix("##") {
                break
            }
        }
    }

    return results
}
