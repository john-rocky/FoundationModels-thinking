import Foundation

// MARK: - Pipeline Classifier

/// Classifies a user query to select the most appropriate pipeline kind.
/// Routes to Direct (simple), Rethink (reasoning), or Verified (constraints).
public struct PipelineClassifier: Sendable {

    public static func classify(
        query: String,
        using modelProvider: any ModelProvider
    ) async -> PipelineKind {
        if let heuristic = heuristicClassify(query) {
            return heuristic
        }
        // Default to Rethink — Verify stage now improves any response,
        // not just reasoning problems. Quality gate prevents degradation.
        return .rethink
    }

    // MARK: - Heuristic Classification

    static func heuristicClassify(_ query: String) -> PipelineKind? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // Very short input: greetings → Direct, follow-ups → Rethink
        if trimmed.count < 15 {
            let greetings = ["hi", "hello", "hey", "thanks", "thank you", "bye",
                             "こんにちは", "おはよう", "ありがとう", "よろしく", "おつかれ"]
            if greetings.contains(where: { lower.contains($0) }) {
                return .direct
            }
            // Short non-greeting = likely a follow-up ("もっと詳しく", "why?", etc.)
            return nil // → falls through to default .rethink
        }

        // Math / logic / puzzle / chase problems → Verified
        let puzzlePatterns = [
            "solve", "equation", "puzzle", "riddle",
            "x + ", "x - ", "x * ", "x = ",
            "catches up", "catch up", "overtake",
            "km/h", "mph", "m/s",
            "求めよ", "方程式", "パズル", "何通り",
            "AはBより", "全員異なる", "制約",
            "追いつ", "時速", "分速", "秒速",
        ]
        if puzzlePatterns.contains(where: { lower.contains($0) }) {
            return .verified
        }

        // Multi-step reasoning / math word problems → Rethink
        let reasoningPatterns = [
            "step 1", "step 2", "calculate", "compute",
            "start with", "if even", "if odd", "swap",
            "how many", "what is the remainder",
            "how long", "how far", "how much", "how fast",
            "ステップ", "計算", "から始め", "偶数なら", "奇数なら",
            "何個", "何匹", "何人", "いくつ", "いくら",
            "何時間", "何分", "何秒", "何km", "何m",
            "速さ",
        ]
        if reasoningPatterns.contains(where: { lower.contains($0) }) {
            return .rethink
        }

        return nil
    }

    // MARK: - LLM Response Parsing

    static func parseLabel(_ response: String) -> PipelineKind {
        let cleaned = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let first = cleaned.first

        if first == "a" { return .direct }
        if first == "c" { return .verified }
        // B and anything else → Rethink
        return .rethink
    }
}
