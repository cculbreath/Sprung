import SwiftUI

/// Knowledge Cards tab using generic CoverflowBrowser with KnowledgeCardView.
struct KnowledgeCardsBrowserTab: View {
    @Binding var cards: [KnowledgeCard]
    let knowledgeCardStore: KnowledgeCardStore
    let onCardUpdated: (KnowledgeCard) -> Void
    let onCardDeleted: (KnowledgeCard) -> Void
    let onCardAdded: (KnowledgeCard) -> Void
    let llmFacade: LLMFacade?

    @Environment(ArtifactRecordStore.self) private var artifactRecordStore
    @Environment(SkillStore.self) private var skillStore

    @State private var selectedFilter: CardTypeFilter = .all
    @State private var searchText = ""
    @State private var editingCard: KnowledgeCard?
    @State private var showDeleteConfirmation = false
    @State private var cardToDelete: KnowledgeCard?
    @State private var showAddSheet = false
    @State private var showIngestionSheet = false
    @State private var pipelineCoordinator: StandaloneKCCoordinator?

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

    /// Cards that haven't been enriched with structured facts yet
    private var unEnrichedCards: [KnowledgeCard] {
        cards.filter { $0.factsJSON == nil && !$0.narrative.isEmpty }
    }

    var body: some View {
        ZStack {
            CoverflowBrowser(
                items: .init(
                    get: { filteredCards },
                    set: { _ in }  // Read-only binding for filtered view
                ),
                cardWidth: 520,
                cardHeight: 500,
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

            // Pipeline progress overlay
            if let coordinator = pipelineCoordinator, coordinator.status.isProcessing {
                pipelineProgressOverlay(coordinator.status)
            }
        }
        .onAppear {
            if pipelineCoordinator == nil {
                pipelineCoordinator = StandaloneKCCoordinator(
                    llmFacade: llmFacade,
                    knowledgeCardStore: knowledgeCardStore,
                    artifactRecordStore: artifactRecordStore,
                    skillStore: skillStore
                )
            }
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

    // MARK: - Filter Bar

    private func filterBar(currentIndex: Binding<Int>) -> some View {
        HStack(spacing: 8) {
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
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 280)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(CardTypeFilter.allCases, id: \.self) { filter in
                        filterChip(filter)
                    }
                }
            }

            Spacer()

            // Pipeline operation buttons
            pipelineButtons

            Divider()
                .frame(height: 20)

            Button(action: { showIngestionSheet = true }) {
                Label("Ingest", systemImage: "tray.and.arrow.down")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .help("Ingest documents or git repos to create knowledge cards")

            Button(action: { showAddSheet = true }) {
                Label("New", systemImage: "plus.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.purple)
            }
            .buttonStyle(.plain)
            .help("Manually create a new knowledge card")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Pipeline Buttons

    @ViewBuilder
    private var pipelineButtons: some View {
        let isProcessing = pipelineCoordinator?.status.isProcessing == true
        let enrichCount = unEnrichedCards.count

        Button(action: runEnrichment) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                Text("Enrich")
                if enrichCount > 0 {
                    Text("\(enrichCount)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.blue.opacity(0.2)))
                }
            }
            .font(.caption)
            .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
        .disabled(enrichCount == 0 || isProcessing)
        .help("Extract structured facts for \(enrichCount) card\(enrichCount == 1 ? "" : "s")")

        Button(action: runMerge) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.merge")
                Text("Merge")
            }
            .font(.caption)
            .foregroundStyle(.green)
        }
        .buttonStyle(.plain)
        .disabled(cards.count < 2 || isProcessing)
        .help("Merge similar cards using AI-powered deduplication")
    }

    // MARK: - Pipeline Actions

    private func runEnrichment() {
        guard let coordinator = pipelineCoordinator else { return }
        let cardsToEnrich = unEnrichedCards

        Task {
            do {
                let count = try await coordinator.enrichCards(cardsToEnrich)
                Logger.info("Pipeline: Enriched \(count) cards", category: .ai)
            } catch {
                Logger.error("Pipeline: Enrichment failed - \(error.localizedDescription)", category: .ai)
            }
        }
    }

    private func runMerge() {
        guard let coordinator = pipelineCoordinator else { return }
        let allCards = Array(cards)

        Task {
            do {
                let (merged, remaining) = try await coordinator.mergeCards(allCards)
                Logger.info("Pipeline: Merged \(merged) cards, \(remaining) remaining", category: .ai)
            } catch {
                Logger.error("Pipeline: Merge failed - \(error.localizedDescription)", category: .ai)
            }
        }
    }

    // MARK: - Progress Overlay

    private func pipelineProgressOverlay(_ status: StandaloneKCCoordinator.Status) -> some View {
        AnimatedThinkingText(statusMessage: status.displayText)
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.1))
    }

    // MARK: - Filter Chips

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
