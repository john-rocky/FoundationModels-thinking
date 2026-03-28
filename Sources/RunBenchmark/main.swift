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
        case "rethink": pipelineKinds = [.rethink]
        case "verified": pipelineKinds = [.verified]
        case "all": pipelineKinds = [.direct, .rethink]
        default:
            print("Usage: RunBenchmark [direct|rethink|verified|all] [problem-ids|all]")
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
        print("\n" + String(repeating: "=", count: 60))
        print("BENCHMARK RESULTS")
        print(String(repeating: "=", count: 60))

        print("\n--- Accuracy ---")
        for kind in pipelineKinds {
            let accuracy = report.pipelineAccuracies[kind] ?? 0
            let avgLatency = report.pipelineLatencies[kind] ?? 0
            let correct = report.results(for: kind).filter(\.isCorrect).count
            let total = report.results(for: kind).count
            let bar = String(repeating: "#", count: Int(accuracy * 20))
                + String(repeating: ".", count: 20 - Int(accuracy * 20))
            print(String(format: "  %-12s %d/%d [\(bar)] %.0f%%  (avg %.1fs)",
                          kind.displayName as NSString,
                          correct, total, accuracy * 100, avgLatency))
        }

        print("\n--- Per Problem ---")
        let colWidth = 14
        var header = "Problem".padding(toLength: 14, withPad: " ", startingAt: 0)
        header += " Expected"
            .padding(toLength: 10, withPad: " ", startingAt: 0)
        for kind in pipelineKinds {
            header += " " + kind.displayName
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

        let incorrect = report.results.filter { !$0.isCorrect }
        if !incorrect.isEmpty {
            print("\n--- Incorrect Answers ---")
            for result in incorrect {
                print("\n[\(result.pipelineKind.displayName)] \(result.problemId)")
                print("  Expected: \(result.expectedAnswer)")
                print("  Got:      \(result.extractedAnswer ?? "(none)")")
                let snippet = String(result.fullOutput.prefix(200))
                    .replacingOccurrences(of: "\n", with: " ")
                print("  Output:   \(snippet)")
            }
        }

        if pipelineKinds.count > 1, let directAcc = report.pipelineAccuracies[.direct] {
            let bestThinking = pipelineKinds.filter { $0 != .direct }
                .compactMap { report.pipelineAccuracies[$0] }.max() ?? 0
            print("\n--- Summary ---")
            print(String(format: "  Direct:   %.0f%%", directAcc * 100))
            print(String(format: "  Rethink:  %.0f%%", bestThinking * 100))
            print(String(format: "  Delta:   %+.0f%%", (bestThinking - directAcc) * 100))
        }
        print(String(format: "  Total time: %.0fs", report.totalDuration))
    }
}
