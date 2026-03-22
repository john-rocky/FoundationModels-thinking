import SwiftUI
import DeepThinkKit

struct ThinkingStreamView: View {
    @Environment(ChatViewModel.self) private var viewModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                // Header with pipeline name and progress
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
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                // Completed steps (compact list)
                if !completedSteps.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(completedSteps) { step in
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                                Text(step.stageName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                }

                // Current streaming content
                if let currentStep = currentRunningStep {
                    Divider()
                        .padding(.horizontal, 12)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.mini)
                            Text(currentStep.stageName)
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                        }

                        if !viewModel.currentStreamingContent.isEmpty {
                            Text(viewModel.currentStreamingContent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(8)
                                .textSelection(.enabled)
                                .contentTransition(.numericText())
                                .animation(.easeOut(duration: 0.05), value: viewModel.currentStreamingContent.count)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .transition(.opacity)
                }

                // Branch progress (for parallel pipelines)
                if let branchStep = currentBranchStep, !branchStep.branchOutputs.isEmpty {
                    Divider()
                        .padding(.horizontal, 12)

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(branchStep.branchOutputs.sorted(by: { $0.key < $1.key }), id: \.key) { name, output in
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                                Text(name)
                                    .font(.caption.bold())
                                Text(String(format: "%.0f%%", output.confidence * 100))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .animation(.spring(duration: 0.3), value: viewModel.thinkingSteps.count)
            .animation(.spring(duration: 0.2), value: viewModel.currentStreamingStageName)

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

    private var completedSteps: [ThinkingStep] {
        viewModel.thinkingSteps.filter {
            if case .completed = $0.status { return true }
            return false
        }
    }

    private var currentRunningStep: ThinkingStep? {
        viewModel.thinkingSteps.last {
            if case .running = $0.status { return true }
            if case .retrying = $0.status { return true }
            return false
        }
    }

    private var currentBranchStep: ThinkingStep? {
        viewModel.thinkingSteps.last {
            $0.stageName.hasPrefix("Parallel") && !$0.branchOutputs.isEmpty
        }
    }
}
