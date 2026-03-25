import SwiftUI
import DeepThinkKit

struct TraceDetailView: View {
    let result: PipelineResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Pipeline overview
            HStack {
                Text("Pipeline: \(result.pipelineName)")
                    .font(.headline)
                Spacer()
                Text("\(result.stageOutputs.count) stages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Stage timeline
            ForEach(Array(result.stageOutputs.enumerated()), id: \.element.id) { index, output in
                StageTraceRow(
                    index: index,
                    output: output,
                    traceRecord: result.trace.first { $0.stageName == output.stageKind.rawValue.capitalized
                        || $0.output == output.content }
                )
            }

            // Summary stats
            HStack(spacing: 16) {
                StatBadge(
                    label: "Total",
                    value: String(format: "%.1fs", result.totalDuration)
                )
                StatBadge(
                    label: "Confidence",
                    value: String(format: "%.0f%%", result.finalOutput.confidence * 100)
                )
                StatBadge(
                    label: "Memory Hits",
                    value: "\(result.trace.flatMap(\.memoryHits).count)"
                )
            }
        }
        .padding()
        .background(AppColors.secondaryBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Stage Trace Row

struct StageTraceRow: View {
    let index: Int
    let output: StageOutput
    let traceRecord: TraceRecord?
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack {
                    Circle()
                        .fill(colorForStage(output.stageKind))
                        .frame(width: 8, height: 8)

                    Text("\(index + 1). \(output.stageKind.rawValue.capitalized)")
                        .font(.subheadline.bold())

                    Spacer()

                    Text(String(format: "%.0f%%", output.confidence * 100))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let record = traceRecord {
                        Text(String(format: "%.2fs", record.duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(output.content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(10)
                    .padding(.leading, 16)
                    .textSelection(.enabled)

                if !output.bulletPoints.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(output.bulletPoints.prefix(5), id: \.self) { point in
                            Text("  \(point)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, 16)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    private func colorForStage(_ kind: StageKind) -> Color {
        switch kind {
        case .analyze: .blue
        case .plan: .purple
        case .solve: .green
        case .critique: .orange
        case .revise: .yellow
        case .finalize: .mint
        case .retrieveMemory: .cyan
        case .summarizeMemory: .indigo
        case .merge: .teal
        case .aggregate: .pink
        case .custom: .gray
        case .webSearch: .blue
        }
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: .capsule)
    }
}
