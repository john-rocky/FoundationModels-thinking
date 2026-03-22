import SwiftUI
import DeepThinkKit

struct ThinkingStreamView: View {
    @Environment(ChatViewModel.self) private var viewModel
    @State private var isExpanded = true

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                Button {
                    withAnimation { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "brain")
                            .foregroundStyle(.tint)
                            .symbolEffect(.pulse, isActive: hasRunningSteps)

                        if let name = viewModel.currentPipelineName {
                            Text("Thinking with \(name)...")
                                .font(.callout.bold())
                                .foregroundStyle(.primary)
                        } else {
                            Text("Thinking...")
                                .font(.callout.bold())
                                .foregroundStyle(.primary)
                        }

                        Spacer()

                        if viewModel.expectedStageCount > 0 {
                            Text("\(completedCount)/\(viewModel.expectedStageCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                if isExpanded && !viewModel.thinkingSteps.isEmpty {
                    Divider()
                        .padding(.horizontal, 12)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.thinkingSteps) { step in
                            ThinkingStepRow(step: step)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .transition(.opacity)
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .animation(.spring(duration: 0.3), value: viewModel.thinkingSteps.count)

            Spacer(minLength: 60)
        }
    }

    private var completedCount: Int {
        viewModel.thinkingSteps.filter {
            if case .completed = $0.status { return true }
            return false
        }.count
    }

    private var hasRunningSteps: Bool {
        viewModel.thinkingSteps.contains {
            if case .running = $0.status { return true }
            return false
        }
    }
}

// MARK: - Thinking Step Row

struct ThinkingStepRow: View {
    let step: ThinkingStep
    @State private var isContentExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                statusIndicator

                Text(step.stageName)
                    .font(.subheadline)
                    .foregroundStyle(isCompleted ? .secondary : .primary)

                Spacer()

                if let output = step.output {
                    Text(String(format: "%.0f%%", output.confidence * 100))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if step.output != nil || !step.branchOutputs.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isContentExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isContentExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isContentExpanded {
                if let output = step.output {
                    Text(output.content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                        .padding(.leading, 20)
                        .textSelection(.enabled)
                        .transition(.opacity)
                }

                if !step.branchOutputs.isEmpty {
                    ForEach(step.branchOutputs.sorted(by: { $0.key < $1.key }), id: \.key) { name, output in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                                .font(.caption.bold())
                            Text(output.content)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                                .textSelection(.enabled)
                        }
                        .padding(.leading, 20)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var isCompleted: Bool {
        if case .completed = step.status { return true }
        return false
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch step.status {
        case .running:
            ProgressView()
                .controlSize(.mini)
                .frame(width: 12, height: 12)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .frame(width: 12, height: 12)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .frame(width: 12, height: 12)
        case .retrying:
            Image(systemName: "arrow.clockwise")
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(width: 12, height: 12)
        }
    }
}
