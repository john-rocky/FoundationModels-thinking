import SwiftUI
import DeepThinkKit

struct ChatView: View {
    @Environment(ChatViewModel.self) private var viewModel
    @State private var showPipelineSelector = false
    @State private var scrollPosition = ScrollPosition(edge: .bottom)

    var body: some View {
        VStack(spacing: 0) {
            messageScrollView
            Divider()
            InputBarView()
        }
        .navigationTitle(viewModel.currentConversation?.title ?? "DeepThink")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                pipelineMenu
            }

            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    viewModel.createNewConversation()
                } label: {
                    Image(systemName: "plus")
                }
            }
            #endif
        }
    }

    private var messageScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if let conversation = viewModel.currentConversation {
                    ForEach(conversation.messages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                    }
                } else {
                    WelcomeView()
                }

                // Both views handle their own visibility internally,
                // keeping observation isolated from the parent ScrollView.
                ThinkingStreamView()
                StreamingAnswerView()
            }
            .padding()
        }
        .defaultScrollAnchor(.bottom)
        .scrollPosition($scrollPosition)
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        // Scroll to bottom on key events.  scrollTo(edge:) is cheap —
        // it sets contentOffset directly without measuring LazyVStack items.
        .onChange(of: viewModel.currentConversation?.messages.count) {
            scrollPosition.scrollTo(edge: .bottom)
        }
        .onChange(of: viewModel.isProcessing) {
            if viewModel.isProcessing {
                scrollPosition.scrollTo(edge: .bottom)
            }
        }
    }

    private var pipelineMenu: some View {
        @Bindable var vm = viewModel
        return Menu {
            Section("Pipeline") {
                ForEach(PipelineKind.allCases) { kind in
                    Button {
                        viewModel.selectedPipelineKind = kind
                    } label: {
                        Label(
                            kind.displayName,
                            systemImage: viewModel.selectedPipelineKind == kind
                                ? "checkmark.circle.fill"
                                : "circle"
                        )
                    }
                }
            }

            Section("Search") {
                Toggle(isOn: $vm.webSearchEnabled) {
                    Label("Web Search", systemImage: "magnifyingglass")
                }
                if vm.webSearchEnabled {
                    Toggle(isOn: $vm.deepSearchEnabled) {
                        Label("Deep Search", systemImage: "magnifyingglass.circle")
                    }
                }
            }
        } label: {
            pipelineMenuLabel
        }
    }

    @ViewBuilder
    private var pipelineMenuLabel: some View {
        if viewModel.selectedPipelineKind == .auto,
           let resolved = viewModel.resolvedPipelineKind {
            Label("Auto → \(resolved.displayName)", systemImage: "sparkles")
        } else {
            Label(
                viewModel.selectedPipelineKind.displayName,
                systemImage: viewModel.selectedPipelineKind == .auto ? "sparkles" : "gearshape"
            )
        }
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "brain")
                .font(.system(size: 60))
                .foregroundStyle(.tint)

            Text("DeepThink")
                .font(.largeTitle.bold())

            Text("Multi-pass reasoning with\nApple Foundation Models")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "arrow.triangle.branch", title: "Multi-Stage Pipeline", description: "Analyze, Plan, Solve, Critique, Revise")
                FeatureRow(icon: "brain.head.profile", title: "External Memory", description: "Session, Working, Long-term memory layers")
                FeatureRow(icon: "eye", title: "Trace & Observe", description: "See what happens at each reasoning stage")
                FeatureRow(icon: "chart.bar", title: "Compare Strategies", description: "Evaluate different reasoning approaches")
            }
            .padding()

            Spacer()
        }
        .padding()
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Streaming Answer (isolated observation boundary)

/// Isolated view that observes only streamingAnswerContent.
/// Prevents per-token changes from invalidating the parent view tree
/// (which would re-diff the entire ForEach message list).
struct StreamingAnswerView: View {
    @Environment(ChatViewModel.self) private var viewModel

    var body: some View {
        if !viewModel.streamingAnswerContent.isEmpty {
            HStack {
                Text(viewModel.streamingAnswerContent)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                Spacer(minLength: 60)
            }
        }
    }
}

// MARK: - Streaming Answer Bubble

struct StreamingAnswerBubble: View {
    let content: String

    var body: some View {
        if content.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    MarkdownContentView(content: content)
                        .textSelection(.enabled)
                        .padding(12)
                        .foregroundStyle(.primary)
                        .background(AppColors.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    Spacer(minLength: 60)
                }
            }
        }
    }
}

// MARK: - Thinking Indicator

struct ThinkingIndicatorView: View {
    @State private var dots = 0
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "brain")
                    .foregroundStyle(.tint)
                Text("Thinking" + String(repeating: ".", count: dots % 4))
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: .capsule)

            Spacer()
        }
        .onReceive(timer) { _ in
            dots += 1
        }
    }
}
