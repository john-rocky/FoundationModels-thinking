import Foundation

// MARK: - Finalize Stage

public struct FinalizeStage: Stage {
    public let kind: StageKind = .finalize
    public let name = "Finalize"
    public let purpose = "Format the final output into a clean, user-friendly form"

    public init() {}

    public func execute(input: StageInput, context: PipelineContext) async throws -> StageOutput {
        await context.traceCollector.record(
            event: .stageStarted(stage: name, kind: kind, input: input.query)
        )

        let bestAnswer = findBestAnswer(from: input.previousOutputs)
        let cleaned = cleanForPresentation(bestAnswer)

        // Emit streaming content so the UI shows progress
        await context.emit(.stageStreamingContent(stageName: name, content: cleaned))

        let output = StageOutput(
            stageKind: .finalize,
            content: cleaned,
            confidence: input.previousOutputs.values
                .sorted { $0.timestamp > $1.timestamp }
                .first?.confidence ?? 0.5
        )

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))

        return output
    }

    /// Remove noise, internal markers, and redundancy for a clean user-facing response.
    private func cleanForPresentation(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var seenContent = Set<String>()

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()

            // Skip confidence/metadata lines
            if lower.hasPrefix("confidence:") || lower.hasPrefix("確信度") { continue }
            if lower.hasPrefix("- confidence:") || lower.hasPrefix("- 確信度") { continue }

            // Skip internal note markers
            if lower.hasPrefix("what was fixed") || lower.hasPrefix("修正箇所") { break }
            if lower.hasPrefix("proposed answer:") || lower.hasPrefix("computation") { continue }
            if lower.hasPrefix("votes:") || lower.hasPrefix("majority:") { continue }

            // Skip prompt echo (model repeating the instructions)
            if lower.contains("end with 'answer:") || lower.contains("answer: [") { continue }
            if lower.contains("write your") && lower.contains("answer") && lower.contains("end with") { continue }

            // Skip duplicate lines (exact content already seen)
            let normalized = trimmed.lowercased()
            if !normalized.isEmpty && seenContent.contains(normalized) { continue }
            if !normalized.isEmpty { seenContent.insert(normalized) }

            result.append(line)
        }

        // Remove trailing blank lines
        while result.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            result.removeLast()
        }
        return result.joined(separator: "\n")
    }

    private func findBestAnswer(from outputs: [String: StageOutput]) -> String {
        if let solved = outputs.first(where: { $0.value.stageKind == .solve })?.value {
            return solved.content
        }
        return outputs.values
            .sorted { $0.timestamp > $1.timestamp }
            .first?.content ?? ""
    }
}
