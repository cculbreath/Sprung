import Foundation
import SwiftyJSON

/// Service responsible for knowledge card workflow: aggregation and generation.
/// Handles the full pipeline from "Done with Uploads" through card generation.
@MainActor
final class KnowledgeCardWorkflowService {
    private let ui: OnboardingUIState
    private let state: StateCoordinator
    private let resRefStore: ResRefStore
    private let eventBus: EventCoordinator
    private let cardMergeService: CardMergeService
    private let chatInventoryService: ChatInventoryService?
    private let agentActivityTracker: AgentActivityTracker
    private weak var sessionUIState: SessionUIState?
    private weak var phaseTransitionController: PhaseTransitionController?

    // LLM facade for prose generation (set after container init due to circular dependency)
    private var llmFacadeProvider: (() -> LLMFacade?)?

    // Aggregated results from "Done with Uploads"
    private var aggregatedSkillBank: SkillBank?
    private var aggregatedNarrativeCards: [KnowledgeCard] = []

    init(
        ui: OnboardingUIState,
        state: StateCoordinator,
        resRefStore: ResRefStore,
        eventBus: EventCoordinator,
        cardMergeService: CardMergeService,
        chatInventoryService: ChatInventoryService?,
        agentActivityTracker: AgentActivityTracker,
        sessionUIState: SessionUIState,
        phaseTransitionController: PhaseTransitionController?
    ) {
        self.ui = ui
        self.state = state
        self.resRefStore = resRefStore
        self.eventBus = eventBus
        self.cardMergeService = cardMergeService
        self.chatInventoryService = chatInventoryService
        self.agentActivityTracker = agentActivityTracker
        self.sessionUIState = sessionUIState
        self.phaseTransitionController = phaseTransitionController
    }

    /// Set the LLM facade provider after container initialization
    func setLLMFacadeProvider(_ provider: @escaping () -> LLMFacade?) {
        self.llmFacadeProvider = provider
    }

    // MARK: - Event Handlers

    /// Handle "Done with Uploads" button click - aggregates skills and narrative cards
    func handleDoneWithUploadsClicked() async {
        Logger.info("📋 Processing Done with Uploads - aggregating skills and narrative cards", category: .ai)

        // Deactivate document collection UI and indicate aggregation is in progress
        ui.isDocumentCollectionActive = false
        ui.isMergingCards = true
        await sessionUIState?.setDocumentCollectionActive(false)

        // Track aggregation in Agents pane
        let agentId = agentActivityTracker.trackAgent(
            type: .cardMerge,
            name: "Aggregating Knowledge",
            task: nil as Task<Void, Never>?
        )

        agentActivityTracker.appendTranscript(
            agentId: agentId,
            entryType: .system,
            content: "Starting skill and narrative card aggregation"
        )

        // Extract chat inventory before aggregation (so it's included)
        if let chatInventoryService = chatInventoryService {
            agentActivityTracker.appendTranscript(
                agentId: agentId,
                entryType: .system,
                content: "Extracting facts from conversation..."
            )
            do {
                if let chatArtifactId = try await chatInventoryService.extractAndCreateArtifact() {
                    agentActivityTracker.appendTranscript(
                        agentId: agentId,
                        entryType: .toolResult,
                        content: "Chat transcript artifact created",
                        details: "ID: \(chatArtifactId)"
                    )
                    Logger.info("💬 Chat inventory extracted and added to artifacts", category: .ai)
                } else {
                    agentActivityTracker.appendTranscript(
                        agentId: agentId,
                        entryType: .system,
                        content: "No career facts found in conversation"
                    )
                }
            } catch {
                Logger.warning("⚠️ Chat inventory extraction failed: \(error.localizedDescription)", category: .ai)
                agentActivityTracker.appendTranscript(
                    agentId: agentId,
                    entryType: .system,
                    content: "Chat extraction skipped: \(error.localizedDescription)"
                )
            }
        }

        // Aggregate skills from all artifacts
        aggregatedSkillBank = await cardMergeService.getMergedSkillBank()
        let skillCount = aggregatedSkillBank?.skills.count ?? 0
        ui.aggregatedSkillBank = aggregatedSkillBank

        // Aggregate narrative cards from all artifacts (with deduplication)
        let rawCards = await cardMergeService.getAllNarrativeCardsFlat()
        let rawCardCount = rawCards.count

        agentActivityTracker.appendTranscript(
            agentId: agentId,
            entryType: .toolResult,
            content: "Aggregated \(skillCount) skills and \(rawCardCount) narrative cards"
        )

        // Run deduplication to merge similar cards across documents
        agentActivityTracker.appendTranscript(
            agentId: agentId,
            entryType: .system,
            content: "Running intelligent deduplication..."
        )

        do {
            let dedupeResult = try await cardMergeService.getAllNarrativeCardsDeduped()
            aggregatedNarrativeCards = dedupeResult.cards
            ui.aggregatedNarrativeCards = aggregatedNarrativeCards

            let mergeCount = dedupeResult.mergeLog.filter { $0.action == .merged }.count
            if mergeCount > 0 {
                agentActivityTracker.appendTranscript(
                    agentId: agentId,
                    entryType: .toolResult,
                    content: "Deduplication: \(rawCardCount) → \(dedupeResult.cards.count) cards (\(mergeCount) merges)"
                )
                Logger.info("🔀 Deduplication: \(rawCardCount) → \(dedupeResult.cards.count) cards (\(mergeCount) merges)", category: .ai)
            } else {
                agentActivityTracker.appendTranscript(
                    agentId: agentId,
                    entryType: .toolResult,
                    content: "Deduplication complete: no duplicates found"
                )
            }
        } catch {
            // Fall back to raw cards if deduplication fails
            Logger.warning("⚠️ Deduplication failed, using raw cards: \(error.localizedDescription)", category: .ai)
            aggregatedNarrativeCards = rawCards
            ui.aggregatedNarrativeCards = aggregatedNarrativeCards
            agentActivityTracker.appendTranscript(
                agentId: agentId,
                entryType: .system,
                content: "Deduplication skipped: \(error.localizedDescription)"
            )
        }

        let cardCount = aggregatedNarrativeCards.count

        // Group cards by type for stats
        var cardsByType: [CardType: Int] = [:]
        for card in aggregatedNarrativeCards {
            cardsByType[card.cardType, default: 0] += 1
        }

        // Build type breakdown string
        var typeBreakdown: [String] = []
        if let count = cardsByType[.employment], count > 0 { typeBreakdown.append("\(count) employment") }
        if let count = cardsByType[.project], count > 0 { typeBreakdown.append("\(count) project") }
        if let count = cardsByType[.achievement], count > 0 { typeBreakdown.append("\(count) achievement") }
        if let count = cardsByType[.education], count > 0 { typeBreakdown.append("\(count) education") }
        let typeSummary = typeBreakdown.joined(separator: ", ")

        // Mark agent complete
        agentActivityTracker.markCompleted(agentId: agentId)
        await eventBus.publish(.mergeComplete(cardCount: cardCount, gapCount: 0))

        // Update UI
        ui.cardAssignmentsReadyForApproval = true
        ui.identifiedGapCount = 0
        ui.isMergingCards = false

        // Notify LLM of results
        let skillSummary = skillCount > 0 ? " and \(skillCount) skills" : ""
        await sendChatMessage("""
            I'm done uploading documents. The system has found \(cardCount) potential knowledge cards (\(typeSummary))\(skillSummary). \
            Please review the proposed cards with me. I can exclude any cards that aren't relevant to me.
            """)
    }

    /// Handle "Generate Cards" button click - converts narrative cards to ResRefs
    func handleGenerateCardsButtonClicked() async {
        Logger.info("🚀 Generate Cards button clicked - converting narrative cards to ResRefs", category: .ai)

        // Read from UI state (which may have been restored from SwiftData)
        let narrativeCards = ui.aggregatedNarrativeCards

        guard !narrativeCards.isEmpty else {
            Logger.error("❌ No narrative cards found - user must click 'Done with Uploads' first", category: .ai)
            await eventBus.publish(.errorOccurred("No cards found. Please upload documents and click 'Done with Uploads' first."))
            return
        }

        // Filter out excluded cards
        let excludedIds = Set(ui.excludedCardIds)
        let cardsToConvert = narrativeCards.filter { !excludedIds.contains($0.id.uuidString) }

        guard !cardsToConvert.isEmpty else {
            Logger.warning("⚠️ All cards have been excluded", category: .ai)
            await eventBus.publish(.errorOccurred("All cards have been excluded. Please include at least one card."))
            return
        }

        Logger.info("🚀 Converting \(cardsToConvert.count) narrative cards to ResRefs (excluded: \(excludedIds.count))", category: .ai)

        // Build artifact ID → filename lookup for source attribution
        let allArtifacts = await state.artifactRecords
        var artifactLookup: [String: String] = [:]
        for artifact in allArtifacts {
            let id = artifact["artifact_id"].stringValue
            let filename = artifact["filename"].stringValue
            if !id.isEmpty && !filename.isEmpty {
                artifactLookup[id] = filename
            }
        }

        // Create converter
        let converter = KnowledgeCardToResRefConverter()

        // Update UI to show progress
        ui.isGeneratingCards = true

        // Clear existing onboarding ResRefs before adding new ones
        // This prevents duplicate accumulation when re-running card generation
        let existingOnboardingCount = resRefStore.resRefs.filter { $0.isFromOnboarding }.count
        if existingOnboardingCount > 0 {
            Logger.info("🗑️ Clearing \(existingOnboardingCount) existing onboarding cards before adding new ones", category: .ai)
            resRefStore.deleteOnboardingResRefs()
        }

        var successCount = 0

        let resRefs = converter.convertAll(
            cards: cardsToConvert,
            artifactLookup: artifactLookup
        ) { completed, total in
            Logger.debug("📊 Card conversion progress: \(completed)/\(total)", category: .ai)
        }

        successCount = resRefs.count

        // Persist all ResRefs and update filesystem mirror
        for resRef in resRefs {
            resRefStore.addResRef(resRef)
            await phaseTransitionController?.updateResRefInFilesystem(resRef)
        }

        Logger.info("✅ Card generation complete: \(successCount) cards persisted", category: .ai)

        ui.isGeneratingCards = false

        // Notify LLM about the results
        await sendChatMessage("Knowledge card generation complete: \(successCount) cards created.")
    }

    // MARK: - Accessors for UI

    /// Get the current aggregated skill bank
    func getAggregatedSkillBank() -> SkillBank? {
        return aggregatedSkillBank
    }

    /// Get the current aggregated narrative cards
    func getAggregatedNarrativeCards() -> [KnowledgeCard] {
        return aggregatedNarrativeCards
    }

    // MARK: - Private Helpers

    private func sendChatMessage(_ text: String) async {
        var userMessage = JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = text
        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
    }
}
