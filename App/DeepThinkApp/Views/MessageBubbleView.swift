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
                    Text(message.content)
                        .textSelection(.enabled)

                    if let result = message.pipelineResult {
                        HStack(spacing: 12) {
                            Label(result.pipelineName, systemImage: "arrow.triangle.branch")
                            Label(
                                String(format: "%.0f%%", result.finalOutput.confidence * 100),
                                systemImage: "gauge"
                            )
                            Label(
                                String(format: "%.1fs", result.totalDuration),
                                systemImage: "clock"
                            )
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)

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
                .padding(12)
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
