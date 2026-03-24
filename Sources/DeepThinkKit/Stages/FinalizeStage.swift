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

        let systemPrompt: String
        let userPrompt: String

        if context.language.isJapanese {
            systemPrompt = "以下の回答をそのまま最終出力として整形してください。内容の追加・削除・言い換えはしないこと。確信度の数値や内部メモのみ除去し、読みやすく整えるだけにしてください。"
            userPrompt = "以下を最終形式に整形してください：\n\n\(truncate(bestAnswer, to: 1000))"
        } else {
            systemPrompt = "Format the following answer as the final output. Only remove confidence numbers and internal notes, and make it readable. Keep all content unchanged."
            userPrompt = "Please format the following into its final form:\n\n\(truncate(bestAnswer, to: 1000))"
        }

        let raw = try await streamingGenerate(
            stageName: name,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            context: context
        )

        let output = parseOutput(raw: raw, kind: .finalize)

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))

        return output
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
