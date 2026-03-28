import SwiftUI
import DeepThinkKit

struct BenchmarkView: View {
    @State private var isRunning = false
    @State private var progress = ""
    @State private var completedCount = 0
    @State private var totalCount = 0
    @State private var report: BenchmarkReport?
    @State private var selectedResult: BenchmarkResult?
    @State private var selectedPipelines: Set<PipelineKind> = [
        .direct, .sequential, .critiqueLoop, .rethink
    ]

    private let problems = BenchmarkProblem.standardSet
    private let runner = BenchmarkRunner()

    private var sortedSelectedPipelines: [PipelineKind] {
        PipelineKind.allCases.filter { selectedPipelines.contains($0) && $0 != .auto }
    }

    var body: some View {
        List {
            configurationSection
            if isRunning {
                progressSection
            }
            if let report {
                summarySection(report)
                resultsGridSection(report)
            }
        }
        .navigationTitle("Benchmark")
        .sheet(item: $selectedResult) { result in
            ResultDetailSheet(result: result)
        }
    }

    // MARK: - Configuration

    private var configurationSection: some View {
        Section("Configuration") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pipelines to benchmark:")
                    .font(.subheadline.bold())

                ForEach(PipelineKind.allCases.filter { $0 != .auto }) { kind in
                    Toggle(isOn: Binding(
                        get: { selectedPipelines.contains(kind) },
                        set: { isOn in
                            if isOn { selectedPipelines.insert(kind) }
                            else { selectedPipelines.remove(kind) }
                        }
                    )) {
                        VStack(alignment: .leading) {
                            Text(kind.displayName)
                            Text(kind.systemDescription)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                }
            }

            Text("\(problems.count) problems x \(selectedPipelines.filter { $0 != .auto }.count) pipelines = \(problems.count * selectedPipelines.filter { $0 != .auto }.count) runs")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                runBenchmark()
            } label: {
                HStack {
                    if isRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isRunning ? "Running..." : "Run Benchmark")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedPipelines.filter({ $0 != .auto }).count < 2 || isRunning)
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        Section("Progress") {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: Double(completedCount), total: Double(max(totalCount, 1)))
                Text(progress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(completedCount)/\(totalCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Summary

    private func summarySection(_ report: BenchmarkReport) -> some View {
        Section("Accuracy Summary") {
            VStack(spacing: 12) {
                // Bar chart
                ForEach(sortedSelectedPipelines) { kind in
                    let accuracy = report.pipelineAccuracies[kind] ?? 0
                    let avgLatency = report.pipelineLatencies[kind] ?? 0
                    HStack {
                        Text(kind.displayName)
                            .font(.caption)
                            .frame(width: 100, alignment: .leading)

                        GeometryReader { geo in
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(barColor(accuracy: accuracy, isDirect: kind == .direct))
                                    .frame(width: max(4, geo.size.width * accuracy))
                                Spacer()
                            }
                        }
                        .frame(height: 20)

                        VStack(alignment: .trailing, spacing: 1) {
                            Text(String(format: "%.0f%%", accuracy * 100))
                                .font(.caption.bold())
                                .foregroundStyle(accuracyColor(accuracy))
                            Text(String(format: "%.1fs", avgLatency))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 48, alignment: .trailing)
                    }
                }

                Divider()

                // Winner
                if let winner = sortedSelectedPipelines.max(by: {
                    (report.pipelineAccuracies[$0] ?? 0) < (report.pipelineAccuracies[$1] ?? 0)
                }) {
                    let directAccuracy = report.pipelineAccuracies[.direct] ?? 0
                    let winnerAccuracy = report.pipelineAccuracies[winner] ?? 0
                    HStack(spacing: 16) {
                        VStack {
                            Text("Best Pipeline")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(winner.displayName)
                                .font(.caption.bold())
                        }

                        if winner != .direct {
                            VStack {
                                Text("vs Direct")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                let delta = winnerAccuracy - directAccuracy
                                Text(String(format: "%+.0f%%", delta * 100))
                                    .font(.caption.bold())
                                    .foregroundStyle(delta > 0 ? .green : delta < 0 ? .red : .secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Results Grid

    private func resultsGridSection(_ report: BenchmarkReport) -> some View {
        Section("Results by Problem") {
            // Header
            HStack(spacing: 0) {
                Text("Problem")
                    .font(.caption2.bold())
                    .frame(width: 120, alignment: .leading)

                ForEach(sortedSelectedPipelines) { kind in
                    Text(shortName(kind))
                        .font(.system(size: 9, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 2)

            // Rows
            ForEach(problems) { problem in
                HStack(spacing: 0) {
                    Text(problem.id)
                        .font(.caption2)
                        .frame(width: 120, alignment: .leading)
                        .lineLimit(1)

                    ForEach(sortedSelectedPipelines) { kind in
                        if let result = report.result(for: problem.id, pipeline: kind) {
                            Button {
                                selectedResult = result
                            } label: {
                                VStack(spacing: 1) {
                                    Image(systemName: result.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(result.isCorrect ? .green : .red)
                                    if let ans = result.extractedAnswer {
                                        Text(ans)
                                            .font(.system(size: 8))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("-")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            // Totals
            HStack(spacing: 0) {
                Text("Score")
                    .font(.caption2.bold())
                    .frame(width: 120, alignment: .leading)

                ForEach(sortedSelectedPipelines) { kind in
                    let correct = report.results(for: kind).filter(\.isCorrect).count
                    let total = report.results(for: kind).count
                    Text("\(correct)/\(total)")
                        .font(.caption2.bold())
                        .foregroundStyle(accuracyColor(Double(correct) / Double(max(total, 1))))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Helpers

    private func runBenchmark() {
        isRunning = true
        report = nil
        completedCount = 0
        totalCount = problems.count * selectedPipelines.filter({ $0 != .auto }).count

        Task {
            let modelProvider = FoundationModelProvider()
            let kinds = sortedSelectedPipelines

            let benchReport = await runner.run(
                problems: problems,
                pipelineKinds: kinds,
                modelProvider: modelProvider
            ) { status, completed, total in
                self.progress = status
                self.completedCount = completed
                self.totalCount = total
            }

            await MainActor.run {
                report = benchReport
                isRunning = false
            }
        }
    }

    private func shortName(_ kind: PipelineKind) -> String {
        switch kind {
        case .direct: "Direct"
        case .sequential: "Seq"
        case .critiqueLoop: "Crit"
        case .branchMerge: "B&M"
        case .selfConsistency: "SC"
        case .verified: "CSP"
        case .rethink: "Rethink"
        case .auto: "Auto"
        }
    }

    private func barColor(accuracy: Double, isDirect: Bool) -> Color {
        if isDirect { return .blue }
        return accuracy >= 0.7 ? .green : accuracy >= 0.4 ? .orange : .red
    }

    private func accuracyColor(_ accuracy: Double) -> Color {
        if accuracy >= 0.7 { return .green }
        if accuracy >= 0.4 { return .orange }
        return .red
    }
}

// MARK: - Result Detail Sheet

struct ResultDetailSheet: View {
    let result: BenchmarkResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Problem") {
                    Text(result.problemQuestion)
                        .font(.callout)
                }

                Section("Expected") {
                    Text(result.expectedAnswer)
                        .font(.headline)
                        .foregroundStyle(.blue)
                }

                Section("Model Output") {
                    HStack {
                        Text("Pipeline:")
                            .font(.caption.bold())
                        Text(result.pipelineKind.displayName)
                            .font(.caption)
                    }

                    HStack {
                        Text("Extracted answer:")
                            .font(.caption.bold())
                        Text(result.extractedAnswer ?? "(none)")
                            .font(.callout.bold())
                            .foregroundStyle(result.isCorrect ? .green : .red)
                    }

                    HStack {
                        Image(systemName: result.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result.isCorrect ? .green : .red)
                        Text(result.isCorrect ? "Correct" : "Incorrect")
                            .font(.caption.bold())
                    }

                    HStack(spacing: 12) {
                        Label(String(format: "%.1fs", result.latency), systemImage: "clock")
                        Label(String(format: "%.0f%%", result.confidence * 100), systemImage: "gauge")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("Full Output") {
                    Text(result.fullOutput)
                        .font(.callout)
                        .textSelection(.enabled)
                }

                if let error = result.errorMessage {
                    Section("Error") {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Result: \(result.problemId)")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
