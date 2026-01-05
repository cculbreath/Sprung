import SwiftUI

/// Knowledge Cards tab using generic CoverflowBrowser with KnowledgeCardView.
struct KnowledgeCardsBrowserTab: View {
    @Binding var cards: [KnowledgeCard]
    let knowledgeCardStore: KnowledgeCardStore
    let onCardUpdated: (KnowledgeCard) -> Void
    let onCardDeleted: (KnowledgeCard) -> Void
    let onCardAdded: (KnowledgeCard) -> Void
    let llmFacade: LLMFacade?

    @State private var selectedFilter: CardTypeFilter = .all
    @State private var searchText = ""
    @State private var editingCard: KnowledgeCard?
    @State private var showDeleteConfirmation = false
    @State private var cardToDelete: KnowledgeCard?
    @State private var showAddSheet = false
    @State private var showIngestionSheet = false

    enum CardTypeFilter: String, CaseIterable {
        case all = "All"
        case job = "Jobs"
        case skill = "Skills"
        case education = "Education"
        case project = "Projects"
        case other = "Other"

        var cardType: String? {
            switch self {
            case .all: return nil
            case .job: return "job"
            case .skill: return "skill"
            case .education: return "education"
            case .project: return "project"
            case .other: return nil
            }
        }
    }

    private var filteredCards: [KnowledgeCard] {
        var result = cards
        if selectedFilter != .all {
            if selectedFilter == .other {
                result = result.filter {
                    guard let type = $0.cardType else { return true }
                    return !["employment", "project", "education", "achievement"].contains(type.rawValue.lowercased())
                }
            } else if let filterType = selectedFilter.cardType {
                result = result.filter { $0.cardType?.rawValue.lowercased() == filterType }
            }
        }
        if !searchText.isEmpty {
            let search = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(search) ||
                $0.narrative.lowercased().contains(search) ||
                ($0.organization?.lowercased().contains(search) ?? false)
            }
        }
        return result
    }

    var body: some View {
        CoverflowBrowser(
            items: .init(
                get: { filteredCards },
                set: { _ in }  // Read-only binding for filtered view
            ),
            cardWidth: 360,
            cardHeight: 420,
            accentColor: .purple
        ) { card, isTopCard in
            // Card content
            KnowledgeCardView(
                card: card,
                isTopCard: isTopCard,
                onEdit: { editingCard = card },
                onDelete: { cardToDelete = card; showDeleteConfirmation = true }
            )
        } filterContent: { currentIndex in
            // Filter bar
            filterBar(currentIndex: currentIndex)
        }
        .sheet(item: $editingCard) { card in
            KnowledgeCardEditSheet(
                card: card,
                onSave: { updated in
                    onCardUpdated(updated)
                    editingCard = nil
                },
                onCancel: { editingCard = nil }
            )
        }
        .sheet(isPresented: $showAddSheet) {
            KnowledgeCardEditSheet(
                card: nil,
                onSave: { newCard in
                    onCardAdded(newCard)
                    showAddSheet = false
                },
                onCancel: { showAddSheet = false }
            )
        }
        .sheet(isPresented: $showIngestionSheet) {
            DocumentIngestionSheet { newCard in
                onCardAdded(newCard)
            }
            .environment(knowledgeCardStore)
        }
        .alert("Delete Card?", isPresented: $showDeleteConfirmation, presenting: cardToDelete) { card in
            Button("Delete", role: .destructive) { onCardDeleted(card) }
            Button("Cancel", role: .cancel) {}
        } message: { card in
            Text("Delete \"\(card.title)\"? This cannot be undone.")
        }
        .onChange(of: selectedFilter) { _, _ in }  // Index reset handled by CoverflowBrowser
        .onChange(of: searchText) { _, _ in }
    }

    private func filterBar(currentIndex: Binding<Int>) -> some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search cards...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                // Ingest button
                Button(action: { showIngestionSheet = true }) {
                    Image(systemName: "arrow.down.doc")
                        .font(.title3)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help("Ingest document to create knowledge cards")

                Button(action: { showAddSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.purple)
                }
                .buttonStyle(.plain)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(CardTypeFilter.allCases, id: \.self) { filter in
                        filterChip(filter)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func filterChip(_ filter: CardTypeFilter) -> some View {
        let isSelected = selectedFilter == filter
        let count = countForFilter(filter)

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
            .background(isSelected ? Color.purple : Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func countForFilter(_ filter: CardTypeFilter) -> Int {
        switch filter {
        case .all:
            return cards.count
        case .other:
            return cards.filter {
                guard let type = $0.cardType else { return true }
                return !["employment", "project", "education", "achievement"].contains(type.rawValue.lowercased())
            }.count
        default:
            guard let filterType = filter.cardType else { return 0 }
            return cards.filter { $0.cardType?.rawValue.lowercased() == filterType }.count
        }
    }
}
