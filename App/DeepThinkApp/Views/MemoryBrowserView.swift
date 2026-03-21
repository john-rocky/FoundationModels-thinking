import SwiftUI
import DeepThinkKit

struct MemoryBrowserView: View {
    @State private var entries: [MemoryEntry] = []
    @State private var searchText = ""
    @State private var selectedKind: MemoryKind?
    @State private var isLoading = false

    private let longTermMemory = LongTermMemory()

    var filteredEntries: [MemoryEntry] {
        var result = entries

        if let kind = selectedKind {
            result = result.filter { $0.kind == kind }
        }

        if !searchText.isEmpty {
            let lower = searchText.lowercased()
            result = result.filter {
                $0.content.lowercased().contains(lower) ||
                $0.tags.contains(where: { $0.lowercased().contains(lower) })
            }
        }

        return result
    }

    var body: some View {
        List {
            if entries.isEmpty && !isLoading {
                ContentUnavailableView(
                    "No Memories",
                    systemImage: "brain.head.profile",
                    description: Text("Memories will be saved automatically as you use the app.")
                )
            }

            // Filter chips
            if !entries.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        FilterChip(title: "All", isSelected: selectedKind == nil) {
                            selectedKind = nil
                        }
                        ForEach(MemoryKind.allCases, id: \.self) { kind in
                            let count = entries.filter { $0.kind == kind }.count
                            if count > 0 {
                                FilterChip(
                                    title: "\(kind.rawValue) (\(count))",
                                    isSelected: selectedKind == kind
                                ) {
                                    selectedKind = kind
                                }
                            }
                        }
                    }
                }
                .listRowSeparator(.hidden)
            }

            ForEach(filteredEntries) { entry in
                MemoryEntryRow(entry: entry)
            }
            .onDelete { indexSet in
                Task {
                    for index in indexSet {
                        let entry = filteredEntries[index]
                        try? await longTermMemory.delete(id: entry.id)
                    }
                    await loadEntries()
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search memories...")
        .navigationTitle("Memory Browser")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await loadEntries() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task {
            await loadEntries()
        }
    }

    private func loadEntries() async {
        isLoading = true
        entries = (try? await longTermMemory.allEntries()) ?? []
        isLoading = false
    }
}

// MARK: - Memory Entry Row

struct MemoryEntryRow: View {
    let entry: MemoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.kind.rawValue.uppercased())
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(colorForKind(entry.kind).opacity(0.2))
                    .clipShape(.capsule)

                if entry.priority >= .high {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }

                Spacer()

                Text(entry.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(entry.content)
                .font(.body)
                .lineLimit(4)

            if !entry.tags.isEmpty {
                HStack {
                    ForEach(entry.tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption2)
                            .foregroundStyle(.tint)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func colorForKind(_ kind: MemoryKind) -> Color {
        switch kind {
        case .fact: .blue
        case .decision: .green
        case .constraint: .orange
        case .summary: .purple
        case .critique: .red
        case .intermediate: .gray
        case .artifact: .mint
        case .question: .yellow
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor : AppColors.secondaryBackground)
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}
