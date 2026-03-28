import Foundation
import DeepThinkKit

@main
struct BenchmarkCLI {
    static let allProblems = BenchmarkProblem.standardSet

    static func main() async {
        let args = CommandLine.arguments
        let pipelineName = args.count > 1 ? args[1] : "all"
        let problemSubset = args.count > 2 ? args[2] : "all"

        let modelProvider = FoundationModelProvider()

        // Quick availability check
        do {
            _ = try await modelProvider.generate(systemPrompt: nil, userPrompt: "Say OK")
        } catch {
            print("ERROR: Model not available - \(error)")
            return
        }

        let problems: [BenchmarkProblem]
        if problemSubset == "all" {
            problems = allProblems
        } else {
            let ids = Set(problemSubset.split(separator: ",").map(String.init))
            problems = allProblems.filter { ids.contains($0.id) }
        }

        let pipelineKinds: [PipelineKind]
        switch pipelineName {
        case "direct": pipelineKinds = [.direct]
        case "sequential": pipelineKinds = [.sequential]
        case "critique": pipelineKinds = [.critiqueLoop]
        case "rethink": pipelineKinds = [.rethink]
        case "branch": pipelineKinds = [.branchMerge]
        case "sc": pipelineKinds = [.selfConsistency]
        case "step": pipelineKinds = [.stepByStep]
        case "all": pipelineKinds = [.direct, .sequential, .critiqueLoop, .rethink, .stepByStep]
        case "thinking": pipelineKinds = [.sequential, .critiqueLoop, .rethink, .stepByStep]
        default:
            print("Usage: RunBenchmark [direct|sequential|critique|rethink|branch|sc|all|thinking] [problem-ids|all]")
            return
        }

        print("Running \(pipelineKinds.map(\.displayName).joined(separator: ", ")) on \(problems.count) problems\n")

        let runner = BenchmarkRunner()
        let report = await runner.run(
            problems: problems,
            pipelineKinds: pipelineKinds,
            modelProvider: modelProvider
        ) { status, completed, total in
            print("[\(completed)/\(total)] \(status)")
        }

        printReport(report, pipelineKinds: pipelineKinds, problems: problems)
    }

    static func printReport(_ report: BenchmarkReport, pipelineKinds: [PipelineKind], problems: [BenchmarkProblem]) {
        print("\n" + String(repeating: "=", count: 70))
        print("BENCHMARK RESULTS")
        print(String(repeating: "=", count: 70))

        print("\n--- Accuracy ---")
        for kind in pipelineKinds {
            let accuracy = report.pipelineAccuracies[kind] ?? 0
            let avgLatency = report.pipelineLatencies[kind] ?? 0
            let correct = report.results(for: kind).filter(\.isCorrect).count
            let total = report.results(for: kind).count
            let bar = String(repeating: "#", count: Int(accuracy * 20))
                + String(repeating: ".", count: 20 - Int(accuracy * 20))
            print(String(format: "  %-20s %d/%d [\(bar)] %.0f%%  (avg %.1fs)",
                          kind.displayName as NSString,
                          correct, total, accuracy * 100, avgLatency))
        }

        // Per-problem grid
        print("\n--- Per Problem ---")
        let colWidth = 14
        var header = "Problem".padding(toLength: 14, withPad: " ", startingAt: 0)
        header += " Expected"
            .padding(toLength: 10, withPad: " ", startingAt: 0)
        for kind in pipelineKinds {
            header += " " + shortName(kind)
                .padding(toLength: colWidth, withPad: " ", startingAt: 0)
        }
        print(header)
        print(String(repeating: "-", count: header.count))

        for problem in problems {
            var line = problem.id
                .padding(toLength: 14, withPad: " ", startingAt: 0)
            line += " " + problem.expectedAnswer
                .padding(toLength: 9, withPad: " ", startingAt: 0)
            for kind in pipelineKinds {
                if let result = report.result(for: problem.id, pipeline: kind) {
                    let mark = result.isCorrect ? "OK" : "NG"
                    let ans = String((result.extractedAnswer ?? "?").prefix(8))
                    let cell = "\(mark) \(ans)"
                    line += " " + cell
                        .padding(toLength: colWidth, withPad: " ", startingAt: 0)
                } else {
                    line += " " + "-"
                        .padding(toLength: colWidth, withPad: " ", startingAt: 0)
                }
            }
            print(line)
        }

        // Incorrect details
        let incorrect = report.results.filter { !$0.isCorrect }
        if !incorrect.isEmpty {
            print("\n--- Incorrect Answers ---")
            for result in incorrect {
                print("\n[\(result.pipelineKind.displayName)] \(result.problemId)")
                print("  Expected: \(result.expectedAnswer)")
                print("  Got:      \(result.extractedAnswer ?? "(none)")")
                let snippet = String(result.fullOutput.prefix(300))
                    .replacingOccurrences(of: "\n", with: " ")
                print("  Output:   \(snippet)")
            }
        }

        if pipelineKinds.count > 1, let directAcc = report.pipelineAccuracies[.direct] {
            let thinkingAccs = pipelineKinds.filter { $0 != .direct }
                .compactMap { report.pipelineAccuracies[$0] }
            let bestThinking = thinkingAccs.max() ?? 0
            print("\n--- Summary ---")
            print(String(format: "  Direct accuracy:         %.0f%%", directAcc * 100))
            print(String(format: "  Best thinking accuracy:  %.0f%%", bestThinking * 100))
            print(String(format: "  Delta:                  %+.0f%%", (bestThinking - directAcc) * 100))
        }
        print(String(format: "  Total time:              %.0fs", report.totalDuration))
    }

    static func shortName(_ kind: PipelineKind) -> String {
        switch kind {
        case .direct: "Direct"
        case .sequential: "Seq"
        case .critiqueLoop: "Critique"
        case .rethink: "Rethink"
        case .stepByStep: "SbS"
        case .branchMerge: "B&M"
        case .selfConsistency: "SC"
        default: kind.displayName
        }
    }
}
