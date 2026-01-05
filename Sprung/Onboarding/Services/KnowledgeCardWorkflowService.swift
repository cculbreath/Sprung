import Foundation
import SwiftyJSON

/// Service responsible for knowledge card workflow: aggregation and generation.
/// Handles the full pipeline from "Done with Uploads" through card approval.
///
/// Workflow:
/// 1. User clicks "Done with Uploads" → aggregates cards/skills with isPending=true
/// 2. User reviews pending cards, deletes unwanted ones
/// 3. User clicks "Approve" → sets isPending=false on remaining cards
@MainActor
final class KnowledgeCardWorkflowService {
    private let ui: OnboardingUIState
    private let state: StateCoordinator
    private let knowledgeCardStore: KnowledgeCardStore
    private let skillStore: SkillStore
    private let eventBus: EventCoordinator
    private let cardMergeService: CardMergeService
    private let chatInventoryService: ChatInventoryService?
    private let agentActivityTracker: AgentActivityTracker
    private weak var sessionUIState: SessionUIState?
    private weak var phaseTransitionController: PhaseTransitionController?

    // LLM facade for prose generation (set after container init due to circular dependency)
    private var llmFacadeProvider: (() -> LLMFacade?)?

    init(
        ui: OnboardingUIState,
        state: StateCoordinator,
        knowledgeCardStore: KnowledgeCardStore,
        skillStore: SkillStore,
        eventBus: EventCoordinator,
        cardMergeService: CardMergeService,
        chatInventoryService: ChatInventoryService?,
        agentActivityTracker: AgentActivityTracker,
        sessionUIState: SessionUIState,
        phaseTransitionController: PhaseTransitionController?
    ) {
        self.ui = ui
        self.state = state
        self.knowledgeCardStore = knowledgeCardStore
        self.skillStore = skillStore
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
    /// Cards are persisted to stores with isPending=true for user review
    func handleDoneWithUploadsClicked() async {
        Logger.info("📋 Processing Done with Uploads - aggregating skills and narrative cards", category: .ai)

        // Deactivate document collection UI and indicate aggregation is in progress
        ui.isDocumentCollectionActive = false
        ui.isMergingCards = true
        await sessionUIState?.setDocumentCollectionActive(false)

        // Clear any existing pending cards before adding new ones
        knowledgeCardStore.deletePendingCards()
        skillStore.deletePendingSkills()

        // Extract chat inventory before aggregation (so it's included)
        if let chatInventoryService = chatInventoryService {
            do {
                if let chatArtifactId = try await chatInventoryService.extractAndCreateArtifact() {
                    Logger.info("💬 Chat inventory extracted and added to artifacts: \(chatArtifactId)", category: .ai)
                }
            } catch {
                Logger.warning("⚠️ Chat inventory extraction failed: \(error.localizedDescription)", category: .ai)
            }
        }

        // Aggregate skills from all artifacts and persist with isPending=true
        if let mergedSkillBank = await cardMergeService.getMergedSkillBank() {
            let skillsToAdd = mergedSkillBank.skills.map { skill -> Skill in
                // Create new Skill with isPending=true and isFromOnboarding=true
                Skill(
                    canonical: skill.canonical,
                    atsVariants: skill.atsVariants,
                    category: skill.category,
                    proficiency: skill.proficiency,
                    evidence: skill.evidence,
                    relatedSkills: skill.relatedSkills,
                    lastUsed: skill.lastUsed,
                    isFromOnboarding: true,
                    isPending: true
                )
            }
            skillStore.addAll(skillsToAdd)
            Logger.info("🔧 Aggregated and persisted \(skillsToAdd.count) skills as pending", category: .ai)
        }

        // Aggregate narrative cards from all artifacts (with deduplication)
        let rawCards = await cardMergeService.getAllNarrativeCardsFlat()
        let rawCardCount = rawCards.count
        Logger.info("📖 Found \(rawCardCount) raw narrative cards", category: .ai)

        var cardsToAdd: [KnowledgeCard]

        // Run deduplication to merge similar cards across documents
        do {
            let dedupeResult = try await cardMergeService.getAllNarrativeCardsDeduped()
            cardsToAdd = dedupeResult.cards
            let mergeCount = dedupeResult.mergeLog.filter { $0.action == .merged }.count
            Logger.info("🔀 Deduplication: \(rawCardCount) → \(dedupeResult.cards.count) cards (\(mergeCount) merges)", category: .ai)
        } catch {
            // Fall back to raw cards if deduplication fails
            Logger.warning("⚠️ Deduplication failed, using raw cards: \(error.localizedDescription)", category: .ai)
            cardsToAdd = rawCards
        }

        // Mark all cards as pending and from onboarding, then persist
        for card in cardsToAdd {
            card.isFromOnboarding = true
            card.isPending = true
        }
        knowledgeCardStore.addAll(cardsToAdd)

        let cardCount = cardsToAdd.count
        let skillCount = skillStore.pendingSkills.count

        // Group cards by type for stats
        var cardsByType: [CardType: Int] = [:]
        for card in cardsToAdd {
            if let cardType = card.cardType {
                cardsByType[cardType, default: 0] += 1
            }
        }

        // Build type breakdown string
        var typeBreakdown: [String] = []
        if let count = cardsByType[.employment], count > 0 { typeBreakdown.append("\(count) employment") }
        if let count = cardsByType[.project], count > 0 { typeBreakdown.append("\(count) project") }
        if let count = cardsByType[.achievement], count > 0 { typeBreakdown.append("\(count) achievement") }
        if let count = cardsByType[.education], count > 0 { typeBreakdown.append("\(count) education") }
        let typeSummary = typeBreakdown.joined(separator: ", ")

        await eventBus.publish(.mergeComplete(cardCount: cardCount, gapCount: 0))

        // Update UI
        ui.cardAssignmentsReadyForApproval = true
        ui.identifiedGapCount = 0
        ui.isMergingCards = false

        // Notify LLM of results
        let skillSummary = skillCount > 0 ? " and \(skillCount) skills" : ""
        await sendChatMessage("""
            I'm done uploading documents. The system has found \(cardCount) potential knowledge cards (\(typeSummary))\(skillSummary). \
            Please review the proposed cards with me. I can delete any cards that aren't relevant.
            """)
    }

    /// Handle "Approve Cards" button click - approves pending knowledge cards and skills
    /// This sets isPending=false on all remaining pending cards/skills
    func handleApproveCardsButtonClicked() async {
        Logger.info("✅ Approve Cards button clicked - approving pending cards and skills", category: .ai)

        let pendingCards = knowledgeCardStore.pendingCards
        let pendingSkills = skillStore.pendingSkills

        guard !pendingCards.isEmpty else {
            Logger.error("❌ No pending cards found - user must click 'Done with Uploads' first", category: .ai)
            await eventBus.publish(.errorOccurred("No cards found. Please upload documents and click 'Done with Uploads' first."))
            return
        }

        // Update UI to show progress
        ui.isGeneratingCards = true

        // Approve all pending cards and skills
        knowledgeCardStore.approveCards()
        skillStore.approveSkills()

        // Update filesystem mirror for each approved card
        let approvedCards = pendingCards  // These were pending, now approved
        for card in approvedCards {
            await phaseTransitionController?.updateKnowledgeCardInFilesystem(card)
        }

        let cardCount = approvedCards.count
        let skillCount = pendingSkills.count
        Logger.info("✅ Approval complete: \(cardCount) cards, \(skillCount) skills approved", category: .ai)

        ui.isGeneratingCards = false
        ui.cardAssignmentsReadyForApproval = false

        // Notify LLM about the results
        let skillSummary = skillCount > 0 ? " and \(skillCount) skills" : ""
        await sendChatMessage("Knowledge cards approved: \(cardCount) cards\(skillSummary) are now available for resume generation.")
    }

    /// Legacy alias for handleApproveCardsButtonClicked
    func handleGenerateCardsButtonClicked() async {
        await handleApproveCardsButtonClicked()
    }

    // MARK: - Private Helpers

    private func sendChatMessage(_ text: String) async {
        var userMessage = JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = text
        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
    }
}
