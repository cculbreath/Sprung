import SwiftUI

/// Knowledge Cards tab using generic CoverflowBrowser with KnowledgeCardView.
struct KnowledgeCardsBrowserTab: View {
    @Binding var cards: [KnowledgeCard]
    let knowledgeCardStore: KnowledgeCardStore
    let onCardUpdated: (KnowledgeCard) -> Void
    let onCardDeleted: (KnowledgeCard) -> Void
    let onCardAdded: (KnowledgeCard) -> Void
    let llmFacade: LLMFacade?
    /// Identity tint for this browser — the Knowledge tab's accent color from
    /// `ReferencesModuleView.Tab.accentColor`, threaded in rather than
    /// hardcoded so the coverflow accent and selected-filter chip always
    /// match the single per-tab identity map.
    let tint: Color

    @Environment(ArtifactRecordStore.self) private var artifactRecordStore
    @Environment(SkillStore.self) private var skillStore
    @Environment(ReasoningStreamState.self) private var reasoningStreamManager

    @State private var selectedFilter: CardTypeFilter = .all
    @State private var searchText = ""
    @State private var editingCard: KnowledgeCard?
    @State private var showDeleteConfirmation = false
    @State private var cardToDelete: KnowledgeCard?
    @State private var showAddSheet = false
    @State private var showIngestionSheet = false
    @State private var refiningCard: KnowledgeCard?
    @State private var reviewContext: RefinementReviewContext?
    @State private var pipelineCoordinator: StandaloneKCCoordinator?
    @State private var pipelineError: String?

    enum CardTypeFilter: String, CaseIterable {
        case all = "All"
        case employment = "Employment"
        case project = "Projects"
        case education = "Education"
        case other = "Other"

        var cardType: CardType? {
            switch self {
            case .all: return nil
            case .employment: return .employment
            case .project: return .project
            case .education: return .education
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
                    return !CardType.allCases.contains(type)
                }
            } else if let filterType = selectedFilter.cardType {
                result = result.filter { $0.cardType == filterType }
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

    /// Cards onboarding persisted but the user never approved (e.g. an
    /// abandoned interview). They feed generation like any other card, so they
    /// must be visible and approvable here rather than ghosting invisibly.
    private var pendingCards: [KnowledgeCard] {
        cards.filter { $0.isPending }
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
                accentColor: tint
            ) { card, isTopCard in
                // Card content
                KnowledgeCardView(
                    card: card,
                    isTopCard: isTopCard,
                    onEdit: { editingCard = card },
                    onDelete: { cardToDelete = card; showDeleteConfirmation = true },
                    onRefine: llmFacade != nil ? { refiningCard = card } : nil,
                    onApprove: { knowledgeCardStore.approveCards(cardIds: [card.id]) }
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
        .sheet(item: $refiningCard) { card in
            KCRefinementSheet(
                card: card,
                onRefine: { instructions, modelId in
                    refiningCard = nil
                    runRefinement(card: card, instructions: instructions, modelId: modelId)
                },
                onCancel: { refiningCard = nil }
            )
        }
        .sheet(item: $reviewContext) { context in
            KCRefinementReviewSheet(
                cardTitle: context.card.title,
                diffs: context.diffs,
                onRetry: { field, feedback in
                    await retryField(card: context.card, field: field, feedback: feedback, modelId: context.modelId)
                },
                onApply: { reviewedDiffs in
                    KCFieldDiff.applyAccepted(reviewedDiffs, to: context.card)
                    onCardUpdated(context.card)
                    reviewContext = nil
                },
                onCancel: { reviewContext = nil }
            )
        }
        .alert("Delete Card?", isPresented: $showDeleteConfirmation, presenting: cardToDelete) { card in
            Button("Delete", role: .destructive) { onCardDeleted(card) }
            Button("Cancel", role: .cancel) {}
        } message: { card in
            Text("Delete \"\(card.title)\"? This cannot be undone.")
        }
        .alert("Operation Failed", isPresented: Binding(
            get: { pipelineError != nil },
            set: { if !$0 { pipelineError = nil } }
        )) {
            Button("OK") { pipelineError = nil }
        } message: {
            Text(pipelineError ?? "")
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
            }
            .buttonStyle(.tintedPill(tint: .orange))
            .help("Ingest documents or git repos to create knowledge cards")

            Button(action: { showAddSheet = true }) {
                Label("New", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.tintedPill(tint: .purple))
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
        let pendingCount = pendingCards.count

        if pendingCount > 0 {
            Button(action: { knowledgeCardStore.approveCards() }) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                    Text("Approve Pending")
                    Text("\(pendingCount)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.25)))
                }
            }
            .buttonStyle(.tintedPill(tint: .orange))
            .disabled(isProcessing)
            .help("Approve \(pendingCount) card\(pendingCount == 1 ? "" : "s") left pending by onboarding")
        }

        Button(action: runEnrichment) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                Text("Enrich")
                if enrichCount > 0 {
                    Text("\(enrichCount)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.blue.opacity(0.25)))
                }
            }
        }
        .buttonStyle(.tintedPill(tint: .blue))
        .disabled(enrichCount == 0 || isProcessing)
        .help("Extract structured facts for \(enrichCount) card\(enrichCount == 1 ? "" : "s")")

        Button(action: runMerge) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.merge")
                Text("Merge")
            }
        }
        .buttonStyle(.tintedPill(tint: .green))
        .disabled(cards.count < 2 || isProcessing)
        .help("Merge similar cards using AI-powered deduplication")
    }

    // MARK: - Refinement

    private func runRefinement(card: KnowledgeCard, instructions: String, modelId: String) {
        guard let llmFacade else { return }

        Task {
            do {
                let service = KCRefinementService(
                    llmFacade: llmFacade,
                    reasoningStreamManager: reasoningStreamManager
                )
                let refined = try await service.refine(
                    card: card,
                    instructions: instructions,
                    modelId: modelId
                )
                // Present the diff for field-by-field review rather than applying
                // blindly — accepted fields only are written, on the user's say-so.
                let diffs = KCFieldDiff.changedFields(before: card, after: refined)
                reviewContext = RefinementReviewContext(card: card, modelId: modelId, diffs: diffs)
            } catch {
                reasoningStreamManager.showError(error.localizedDescription)
                Logger.error("KC Refinement failed: \(error.localizedDescription)", category: .ai)
            }
        }
    }

    /// Re-refine a single field with feedback for the review sheet's Retry. Returns
    /// the new value, or nil on failure (logged; the sheet surfaces a retry prompt).
    private func retryField(card: KnowledgeCard, field: KCField, feedback: String, modelId: String) async -> KCFieldValue? {
        guard let llmFacade else { return nil }
        let service = KCRefinementService(
            llmFacade: llmFacade,
            reasoningStreamManager: reasoningStreamManager
        )
        do {
            return try await service.refineField(card: card, field: field, feedback: feedback, modelId: modelId)
        } catch {
            Logger.error("KC field retry failed: \(error.localizedDescription)", category: .ai)
            return nil
        }
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
                pipelineError = "Couldn't enrich your cards — \(error.localizedDescription)"
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
                pipelineError = "Couldn't merge your cards — \(error.localizedDescription)"
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
            .background(isSelected ? tint : Color(nsColor: .controlBackgroundColor))
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
                return !CardType.allCases.contains(type)
            }.count
        default:
            guard let filterType = filter.cardType else { return 0 }
            return cards.filter { $0.cardType == filterType }.count
        }
    }
}

/// Holds the in-flight refinement under review: the card, the model used (for
/// per-field retry), and the changed-field diff the sheet renders.
private struct RefinementReviewContext: Identifiable {
    let id = UUID()
    let card: KnowledgeCard
    let modelId: String
    let diffs: [KCFieldDiff]
}
