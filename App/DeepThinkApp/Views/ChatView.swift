import SwiftUI
import DeepThinkKit

struct ChatView: View {
    @Environment(ChatViewModel.self) private var viewModel
    @State private var showPipelineSelector = false

    var body: some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
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

                        if viewModel.isProcessing {
                            ThinkingStreamView()
                                .id("thinking")
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.currentConversation?.messages.count) {
                    if let lastId = viewModel.currentConversation?.messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.thinkingSteps.count) {
                    if viewModel.isProcessing {
                        withAnimation {
                            proxy.scrollTo("thinking", anchor: .bottom)
                        }
                    }
                }
                .onTapGesture {
                    #if os(iOS)
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    #endif
                }
            }

            Divider()

            // Input Area
            InputBarView()
        }
        .navigationTitle(viewModel.currentConversation?.title ?? "DeepThink")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
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
                } label: {
                    Label(viewModel.selectedPipelineKind.displayName, systemImage: "gearshape")
                }
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
