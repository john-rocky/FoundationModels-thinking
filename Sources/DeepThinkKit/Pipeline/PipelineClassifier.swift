import Foundation

// MARK: - Pipeline Classifier

/// Classifies a user query to select the most appropriate pipeline kind.
/// Combines rule-based heuristics with a short LLM call for robust classification.
public struct PipelineClassifier: Sendable {

    /// Classify a user query into the most appropriate pipeline kind.
    public static func classify(
        query: String,
        using modelProvider: any ModelProvider
    ) async -> PipelineKind {
        // Rule-based fast path for clear-cut cases
        if let heuristic = heuristicClassify(query) {
            return heuristic
        }

        let userPrompt = """
            Pick ONE label for the following question. Reply with the label letter only.

            A: Simple greeting, single-fact lookup, translation, or definition.
            B: Needs careful verification. Factual explanation, technical topic, or anything where correctness matters.
            C: Multiple valid viewpoints. Comparison, trade-offs, or exploring different approaches.
            D: Has one correct answer that can be computed. Math, logic, or constraint-based problem.
            E: Step-by-step task. How-to, planning, coding, or creative writing.

            Question: \(String(query.prefix(400)))
            """

        do {
            let raw = try await modelProvider.generate(
                systemPrompt: nil,
                userPrompt: userPrompt
            )
            return parseLabel(raw)
        } catch {
            return .critiqueLoop
        }
    }

    // MARK: - Heuristic Classification

    /// Fast rule-based classification for obvious cases.
    /// Returns nil if heuristics are inconclusive and LLM should decide.
    static func heuristicClassify(_ query: String) -> PipelineKind? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // Very short input is likely a greeting or simple lookup
        if trimmed.count < 15 {
            let greetings = ["hi", "hello", "hey", "thanks", "thank you", "bye",
                             "こんにちは", "おはよう", "ありがとう", "よろしく", "おつかれ"]
            if greetings.contains(where: { lower.contains($0) }) {
                return .direct
            }
        }

        // Math / logic / puzzle indicators
        let puzzlePatterns = [
            "solve", "calculate", "compute", "equation",
            "puzzle", "riddle", "logic",
            "x + ", "x - ", "x * ", "x = ",
            "求めよ", "計算", "方程式", "パズル", "何通り",
            "AはBより", "全員異なる", "制約"
        ]
        if puzzlePatterns.contains(where: { lower.contains($0) }) {
            return .verified
        }

        // Debate / multi-perspective indicators
        let debatePatterns = [
            "pros and cons", "advantages and disadvantages",
            "compare", "vs ", " or ",
            "メリットとデメリット", "賛否", "比較", "どちらが",
            "should we", "is it better"
        ]
        if debatePatterns.contains(where: { lower.contains($0) }) {
            return .branchMerge
        }

        return nil
    }

    /// Detect queries that would benefit from web search (factual, current events, lookup).
    public static func shouldWebSearch(_ query: String) -> Bool {
        let lower = query.lowercased()
        let factualPatterns = [
            "what is", "who is", "when did", "where is", "how many", "how much",
            "latest", "current", "recent", "today", "news",
            "what happened", "is it true", "tell me about",
            "とは", "って何", "いつ", "最新", "ニュース", "現在", "今の",
            "について教えて", "誰が", "何が",
        ]
        return factualPatterns.contains(where: { lower.contains($0) })
    }

    // MARK: - LLM Response Parsing

    /// Parse the model's A/B/C/D/E label response into a PipelineKind.
    static func parseLabel(_ response: String) -> PipelineKind {
        let cleaned = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        // Check for label letter anywhere in the response
        let first = cleaned.first

        if first == "a" || cleaned.contains("simple") {
            return .direct
        }
        if first == "b" || cleaned.contains("review") {
            return .critiqueLoop
        }
        if first == "c" || cleaned.contains("debate") {
            return .branchMerge
        }
        if first == "d" || cleaned.contains("puzzle") {
            return .verified
        }
        if first == "e" || cleaned.contains("other") {
            return .sequential
        }

        // Legacy keyword fallback
        let words = cleaned.components(separatedBy: .whitespacesAndNewlines)
        let firstWord = words.first ?? ""

        switch firstWord {
        case "direct":
            return .direct
        case "critiqueloop", "critique":
            return .critiqueLoop
        case "branchmerge", "branch":
            return .branchMerge
        case "verified", "verify":
            return .verified
        case "sequential":
            return .sequential
        default:
            return .critiqueLoop
        }
    }
}
