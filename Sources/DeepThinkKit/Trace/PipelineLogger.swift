import Foundation

// MARK: - Pipeline Logger

/// Prints structured logs of each pipeline stage's thinking process and results.
/// Enabled only in DEBUG builds. Useful for comparing Direct vs multi-pass pipelines.
enum PipelineLogger {

    private static let separator = "══════════════════════════════════════════════════════════════"
    private static let divider   = "──────────────────────────────────────────────────────────────"

    static func log(_ event: PipelineEvent) {
        #if DEBUG
        switch event {
        case .pipelineStarted(let name, let stageCount):
            print("""

            \(separator)
            [Pipeline: \(name)] Started — \(stageCount) stages
            \(separator)
            """)

        case .stageStarted(let stageName, _, let index):
            print("\n\(divider)")
            print("[\(index + 1)] \(stageName) — running...")

        case .stageCompleted(let stageName, let stageKind, let output, let index):
            let conf = String(format: "%.0f%%", output.confidence * 100)
            let preview = truncateForLog(output.content, maxLines: 30)
            print("""
            [\(index + 1)] \(stageName) (\(stageKind.rawValue)) — confidence: \(conf)
            \(preview)
            """)

        case .stageFailed(let stageName, let error):
            print("[\(stageName)] FAILED: \(error)")

        case .stageRetrying(let stageName, let attempt):
            print("[\(stageName)] Retrying (attempt \(attempt))...")

        case .branchesStarted(let names):
            print("\n\(divider)")
            print("[Branches] Started: \(names.joined(separator: ", "))")

        case .branchCompleted(let branchName, let output):
            let conf = String(format: "%.0f%%", output.confidence * 100)
            let preview = truncateForLog(output.content, maxLines: 15)
            print("""
            [Branch: \(branchName)] — confidence: \(conf)
            \(preview)
            """)

        case .loopIterationStarted(let iteration, let max):
            print("\n\(divider)")
            print("[Loop] Iteration \(iteration)/\(max)")

        case .loopEnded(let reason):
            print("[Loop] Ended — \(reason)")

        case .pipelineCompleted(let result):
            let duration = String(format: "%.1f", result.totalDuration)
            let conf = String(format: "%.0f%%", result.finalOutput.confidence * 100)

            // Per-stage timing from trace records
            let stageTimings = result.trace
                .filter { $0.duration > 0 }
                .map { "\($0.stageName): \(String(format: "%.1fs", $0.duration))" }
                .joined(separator: " → ")

            print("""

            \(separator)
            [Pipeline: \(result.pipelineName)] Completed
            Query: \(result.query)
            Duration: \(duration)s | Stages: \(result.stageOutputs.count) | Confidence: \(conf)
            Timing: \(stageTimings.isEmpty ? "N/A" : stageTimings)
            \(divider)
            Final output:
            \(result.finalOutput.content)
            \(separator)
            """)

        case .pipelineFailed(let error):
            print("""

            \(separator)
            [Pipeline] FAILED: \(error)
            \(separator)
            """)

        case .stageStreamingContent:
            break

        case .webSearchStarted(let keywords):
            print("\n\(divider)")
            print("[WebSearch] Searching: \(keywords)")

        case .webSearchCompleted(let count):
            print("[WebSearch] Found \(count) results")

        case .webSearchSkipped(let reason):
            print("[WebSearch] Skipped: \(reason)")

        case .webPageFetchStarted(let count):
            print("[WebSearch] Fetching \(count) pages...")

        case .webPageFetchCompleted(let successCount):
            print("[WebSearch] Fetched \(successCount) pages")

        case .webContentExtracting:
            print("[WebSearch] Extracting core information...")

}
        #endif
    }

    private static func truncateForLog(_ text: String, maxLines: Int) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count <= maxLines {
            return text
        }
        let kept = lines.prefix(maxLines).joined(separator: "\n")
        return kept + "\n... (\(lines.count - maxLines) more lines)"
    }
}
