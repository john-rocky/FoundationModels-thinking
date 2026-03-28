import SwiftUI
import DeepThinkKit

struct ContentView: View {
    @Environment(ChatViewModel.self) private var viewModel

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            SidebarView()
        } detail: {
            ChatView()
        }
        #else
        TabView {
            Tab("Chat", systemImage: "bubble.left.and.bubble.right") {
                NavigationStack {
                    ChatView()
                }
            }
            Tab("Benchmark", systemImage: "chart.bar.xaxis") {
                NavigationStack {
                    BenchmarkView()
                }
            }
            Tab("Compare", systemImage: "chart.bar") {
                NavigationStack {
                    ComparisonView()
                }
            }
            Tab("Memory", systemImage: "brain.head.profile") {
                NavigationStack {
                    MemoryBrowserView()
                }
            }
        }
        #endif
    }
}

// MARK: - Sidebar (macOS)

struct SidebarView: View {
    @Environment(ChatViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        List(selection: $vm.selectedConversationId) {
            Section("Conversations") {
                ForEach(viewModel.conversations) { conversation in
                    NavigationLink(value: conversation.id) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(conversation.title)
                                .lineLimit(1)
                                .font(.body)
                            Text(conversation.pipelineKind.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            viewModel.deleteConversation(id: conversation.id)
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    viewModel.createNewConversation()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .navigationTitle("DeepThink")
    }
}
