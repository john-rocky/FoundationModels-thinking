import SwiftUI
import DeepThinkKit

struct ComparisonView: View {
    @State private var query = ""
    @State private var isRunning = false
    @State private var results: [ComparisonEntry] = []
    @State private var selectedPipelines: Set<PipelineKind> = [.direct, .critiqueLoop]
    @State private var runningPipeline: String?

    var body: some View {
        List {
            Section("Configuration") {
                TextField("Enter a query to compare...", text: $query, axis: .vertical)
                    .lineLimit(2...5)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Pipelines to compare:")
                        .font(.subheadline.bold())

                    ForEach(PipelineKind.allCases) { kind in
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

                Button {
                    runComparison()
                } label: {
                    HStack {
                        if isRunning {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isRunning
                             ? "Running \(runningPipeline ?? "")..."
                             : "Run Comparison")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(query.isEmpty || selectedPipelines.count < 2 || isRunning)

                if selectedPipelines.count < 2 {
                    Text("Select at least 2 pipelines to compare")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if !results.isEmpty {
                // Summary comparison
                Section("Summary") {
                    ComparisonSummaryView(results: results)
                }

                // Individual results
                Section("Details") {
                    ForEach(results) { entry in
                        ComparisonRow(entry: entry)
                    }
                }

                // Side-by-side output diff
                if results.filter({ $0.result != nil }).count >= 2 {
                    Section("Output Comparison") {
                        OutputDiffView(results: results.filter { $0.result != nil })
                    }
                }
            }
        }
        .navigationTitle("Strategy Comparison")
    }

    private func runComparison() {
        guard !query.isEmpty else { return }
        isRunning = true
        results = []

        Task {
            let modelProvider = FoundationModelProvider()
            var newResults: [ComparisonEntry] = []

            for kind in selectedPipelines.sorted(by: { $0.rawValue < $1.rawValue }) {
                await MainActor.run {
                    runningPipeline = kind.displayName
                }

                let pipeline = PipelineFactory.create(kind: kind)
                let context = PipelineContext(modelProvider: modelProvider)

                do {
                    let result = try await pipeline.execute(query: query, context: context)
                    let metrics = EvaluationMetrics(from: result)
                    newResults.append(ComparisonEntry(
                        pipelineKind: kind,
                        result: result,
                        metrics: metrics,
                        error: nil
                    ))
                } catch {
                    let desc: String
                    if let se = error as? StageError {
                        desc = se.errorDescription ?? "\(se)"
                    } else {
                        desc = "\(error)"
                    }
                    newResults.append(ComparisonEntry(
                        pipelineKind: kind,
                        result: nil,
                        metrics: nil,
                        error: desc
                    ))
                }
            }

            await MainActor.run {
                results = newResults
                isRunning = false
                runningPipeline = nil
            }
        }
    }
}

// MARK: - Comparison Entry

struct ComparisonEntry: Identifiable {
    let id = UUID()
    let pipelineKind: PipelineKind
    let result: PipelineResult?
    let metrics: EvaluationMetrics?
    let error: String?
}

// MARK: - Comparison Summary

struct ComparisonSummaryView: View {
    let results: [ComparisonEntry]

    private var successfulResults: [ComparisonEntry] {
        results.filter { $0.metrics != nil }
    }

    private var fastest: ComparisonEntry? {
        successfulResults.min { ($0.metrics?.totalLatency ?? .infinity) < ($1.metrics?.totalLatency ?? .infinity) }
    }

    private var highestConfidence: ComparisonEntry? {
        successfulResults.max { ($0.metrics?.averageConfidence ?? 0) < ($1.metrics?.averageConfidence ?? 0) }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Bar chart style comparison
            ForEach(successfulResults) { entry in
                HStack {
                    Text(entry.pipelineKind.displayName)
                        .font(.caption)
                        .frame(width: 100, alignment: .leading)

                    // Latency bar
                    let maxLatency = successfulResults.compactMap { $0.metrics?.totalLatency }.max() ?? 1
                    let latency = entry.metrics?.totalLatency ?? 0
                    GeometryReader { geo in
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(entry.pipelineKind == .direct ? Color.blue : Color.orange)
                                .frame(width: max(4, geo.size.width * latency / maxLatency))
                            Text(String(format: "%.1fs", latency))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 20)

                    // Confidence
                    Text(String(format: "%.0f%%", (entry.metrics?.averageConfidence ?? 0) * 100))
                        .font(.caption.bold())
                        .foregroundStyle(confidenceColor(entry.metrics?.averageConfidence ?? 0))
                        .frame(width: 40, alignment: .trailing)
                }
            }

            Divider()

            HStack(spacing: 20) {
                if let fast = fastest {
                    VStack {
                        Text("Fastest")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(fast.pipelineKind.displayName)
                            .font(.caption.bold())
                    }
                }
                if let best = highestConfidence {
                    VStack {
                        Text("Highest Confidence")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(best.pipelineKind.displayName)
                            .font(.caption.bold())
                    }
                }

                let directLatency = results.first(where: { $0.pipelineKind == .direct })?.metrics?.totalLatency
                let thinkingLatency = results.first(where: { $0.pipelineKind != .direct && $0.metrics != nil })?.metrics?.totalLatency
                if let d = directLatency, let t = thinkingLatency, d > 0 {
                    VStack {
                        Text("Thinking Overhead")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1fx", t / d))
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.7 { return .green }
        if confidence >= 0.4 { return .orange }
        return .red
    }
}

// MARK: - Output Diff View

struct OutputDiffView: View {
    let results: [ComparisonEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(results) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label(entry.pipelineKind.displayName, systemImage: entry.pipelineKind.isMultiPass ? "brain" : "bolt")
                            .font(.subheadline.bold())
                            .foregroundStyle(entry.pipelineKind == .direct ? .blue : .orange)

                        Spacer()

                        if let metrics = entry.metrics {
                            Text(String(format: "%.1fs", metrics.totalLatency))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    MarkdownContentView(content: entry.result?.finalOutput.content ?? "")
                        .font(.callout)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColors.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Show stage count for multi-pass
                    if let result = entry.result, entry.pipelineKind.isMultiPass {
                        HStack(spacing: 8) {
                            ForEach(result.stageOutputs, id: \.id) { stage in
                                Text(stage.stageKind.rawValue)
                                    .font(.system(size: 9))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(stageColor(stage.stageKind).opacity(0.2))
                                    .clipShape(.capsule)
                            }
                        }
                    }
                }
            }
        }
    }

    private func stageColor(_ kind: StageKind) -> Color {
        switch kind {
        case .analyze: .blue
        case .plan: .purple
        case .solve: .green
        case .critique: .orange
        case .revise: .yellow
        case .finalize: .mint
        default: .gray
        }
    }
}

// MARK: - Comparison Row

struct ComparisonRow: View {
    let entry: ComparisonEntry
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack {
                    Image(systemName: entry.pipelineKind.isMultiPass ? "brain" : "bolt")
                        .foregroundStyle(entry.pipelineKind == .direct ? .blue : .orange)

                    VStack(alignment: .leading) {
                        Text(entry.pipelineKind.displayName)
                            .font(.headline)
                        Text(entry.pipelineKind.systemDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let metrics = entry.metrics {
                        VStack(alignment: .trailing) {
                            Text(String(format: "%.0f%%", metrics.averageConfidence * 100))
                                .font(.title3.bold())
                                .foregroundStyle(confidenceColor(metrics.averageConfidence))
                            HStack(spacing: 4) {
                                Text(String(format: "%.1fs", metrics.totalLatency))
                                Text("\(metrics.stageCount) stages")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    } else if entry.error != nil {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                if let result = entry.result {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Output:")
                            .font(.subheadline.bold())
                        MarkdownContentView(content: result.finalOutput.content)
                            .font(.callout)
                            .lineLimit(20)
                            .textSelection(.enabled)

                        if let metrics = entry.metrics {
                            Divider()
                            MetricsGrid(metrics: metrics)
                        }
                    }
                    .padding(.top, 4)
                }

                if let error = entry.error {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.7 { return .green }
        if confidence >= 0.4 { return .orange }
        return .red
    }
}

// MARK: - Metrics Grid

struct MetricsGrid: View {
    let metrics: EvaluationMetrics

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
        ], spacing: 8) {
            MetricCell(label: "Stages", value: "\(metrics.stageCount)")
            MetricCell(label: "Confidence", value: String(format: "%.0f%%", metrics.averageConfidence * 100))
            MetricCell(label: "Latency", value: String(format: "%.1fs", metrics.totalLatency))
            MetricCell(label: "Parse Rate", value: String(format: "%.0f%%", metrics.parseSuccessRate * 100))
            MetricCell(label: "Memory Hits", value: String(format: "%.0f%%", metrics.memoryHitRate * 100))
            MetricCell(label: "Improvement", value: String(format: "%.0f%%", metrics.critiqueImprovementRate * 100))
        }
    }
}

struct MetricCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(6)
        .background(AppColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
