import SwiftUI
import DeepThinkKit

struct MessageBubbleView: View {
    let message: ChatMessage
    @State private var showTrace = false

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            HStack {
                if message.role == .user { Spacer(minLength: 60) }

                VStack(alignment: .leading, spacing: 8) {
                    if message.role == .assistant {
                        MarkdownContentView(content: message.content)
                            .textSelection(.enabled)
                    } else {
                        Text(message.content)
                            .textSelection(.enabled)
                    }

                    // Show pipeline metadata (from live result or persisted data)
                    if let name = message.pipelineResult?.pipelineName ?? message.pipelineName {
                        let confidence = message.pipelineResult?.finalOutput.confidence ?? message.pipelineConfidence ?? 0
                        let duration = message.pipelineResult?.totalDuration ?? message.pipelineDuration ?? 0

                        HStack(spacing: 12) {
                            Label(name, systemImage: "arrow.triangle.branch")
                            Label(
                                String(format: "%.0f%%", confidence * 100),
                                systemImage: "gauge"
                            )
                            Label(
                                String(format: "%.1fs", duration),
                                systemImage: "clock"
                            )
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                        if message.pipelineResult != nil {
                            Button {
                                showTrace.toggle()
                            } label: {
                                Label(
                                    showTrace ? "Hide Trace" : "Show Trace",
                                    systemImage: showTrace ? "chevron.up" : "chevron.down"
                                )
                                .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tint)
                        }
                    }
                }
                .padding(12)
                .foregroundStyle(message.role == .user ? .white : .primary)
                .background(backgroundFor(role: message.role))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                if message.role != .user { Spacer(minLength: 60) }
            }

            if showTrace, let result = message.pipelineResult {
                TraceDetailView(result: result)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: showTrace)
    }

    private func backgroundFor(role: MessageRole) -> Color {
        switch role {
        case .user:
            Color.accentColor
        case .assistant:
            AppColors.secondaryBackground
        case .system:
            Color.red.opacity(0.15)
        }
    }
}
