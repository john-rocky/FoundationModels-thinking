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

    /// Remove confidence scores, internal notes, and trailing metadata without using the model.
    private func cleanForPresentation(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            // Skip confidence lines
            if trimmed.hasPrefix("confidence:") || trimmed.hasPrefix("確信度") {
                continue
            }
            if trimmed.hasPrefix("- confidence:") || trimmed.hasPrefix("- 確信度") {
                continue
            }
            // Skip internal note markers
            if trimmed.hasPrefix("what was fixed") || trimmed.hasPrefix("修正箇所") {
                break
            }
            result.append(line)
        }
        // Remove trailing blank lines
        while result.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            result.removeLast()
        }
        return result.joined(separator: "\n")
    }

    private func findBestAnswer(from outputs: [String: StageOutput]) -> String {
        if let revised = outputs.first(where: { $0.value.stageKind == .revise })?.value {
            return revised.content
        }
        if let solved = outputs.first(where: { $0.value.stageKind == .solve })?.value {
            return solved.content
        }
        if let merged = outputs.first(where: { $0.value.stageKind == .merge })?.value {
            return merged.content
        }
        if let aggregated = outputs.first(where: { $0.value.stageKind == .aggregate })?.value {
            return aggregated.content
        }
        return outputs.values
            .sorted { $0.timestamp > $1.timestamp }
            .first?.content ?? ""
    }
}
