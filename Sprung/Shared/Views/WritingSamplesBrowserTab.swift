import SwiftUI

/// Writing Samples tab using generic CoverflowBrowser with CoverRefCardView.
struct WritingSamplesBrowserTab: View {
    @Binding var cards: [CoverRef]
    let onCardUpdated: (CoverRef) -> Void
    let onCardDeleted: (CoverRef) -> Void
    let onCardAdded: (CoverRef) -> Void

    @State private var selectedFilter: SampleTypeFilter = .all
    @State private var searchText = ""
    @State private var editingCard: CoverRef?
    @State private var showDeleteConfirmation = false
    @State private var cardToDelete: CoverRef?
    @State private var showAddSheet = false
    @State private var newCardType: CoverRefType = .backgroundFact

    enum SampleTypeFilter: String, CaseIterable {
        case all = "All"
        case backgroundFacts = "Background Facts"
        case writingSamples = "Writing Samples"
    }

    private var filteredCards: [CoverRef] {
        var result = cards

        switch selectedFilter {
        case .all: break
        case .backgroundFacts:
            result = result.filter { $0.type == .backgroundFact }
        case .writingSamples:
            result = result.filter { $0.type == .writingSample }
        }

        if !searchText.isEmpty {
            let search = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(search) ||
                $0.content.lowercased().contains(search)
            }
        }

        return result
    }

    var body: some View {
        CoverflowBrowser(
            items: .init(
                get: { filteredCards },
                set: { _ in }
            ),
            cardWidth: 520,
            cardHeight: 500,
            accentColor: .blue
        ) { card, isTopCard in
            CoverRefCardView(
                coverRef: card,
                isTopCard: isTopCard,
                onEdit: { editingCard = card },
                onDelete: { cardToDelete = card; showDeleteConfirmation = true }
            )
        } filterContent: { currentIndex in
            filterBar(currentIndex: currentIndex)
        }
        .sheet(item: $editingCard) { card in
            CoverRefEditSheet(
                card: card,
                onSave: { updated in
                    onCardUpdated(updated)
                    editingCard = nil
                },
                onCancel: { editingCard = nil }
            )
        }
        .sheet(isPresented: $showAddSheet) {
            CoverRefEditSheet(
                card: nil,
                defaultType: newCardType,
                onSave: { newCard in
                    onCardAdded(newCard)
                    showAddSheet = false
                },
                onCancel: { showAddSheet = false }
            )
        }
        .alert("Delete Reference?", isPresented: $showDeleteConfirmation, presenting: cardToDelete) { card in
            Button("Delete", role: .destructive) { onCardDeleted(card) }
            Button("Cancel", role: .cancel) {}
        } message: { card in
            Text("Delete \"\(card.name)\"? This cannot be undone.")
        }
    }

    private func filterBar(currentIndex: Binding<Int>) -> some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search references...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                // Add menu
                Menu {
                    Button(action: {
                        newCardType = .backgroundFact
                        showAddSheet = true
                    }) {
                        Label("Background Fact", systemImage: "info.circle")
                    }
                    Button(action: {
                        newCardType = .writingSample
                        showAddSheet = true
                    }) {
                        Label("Writing Sample", systemImage: "doc.text")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
                .menuStyle(.borderlessButton)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(SampleTypeFilter.allCases, id: \.self) { filter in
                        filterChip(filter)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func filterChip(_ filter: SampleTypeFilter) -> some View {
        let isSelected = selectedFilter == filter
        let count = countFor(filter)

        return Button(action: { selectedFilter = filter }) {
            HStack(spacing: 4) {
                Text(filter.rawValue)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.15)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func countFor(_ filter: SampleTypeFilter) -> Int {
        switch filter {
        case .all: return cards.count
        case .backgroundFacts: return cards.filter { $0.type == .backgroundFact }.count
        case .writingSamples: return cards.filter { $0.type == .writingSample }.count
        }
    }
}
