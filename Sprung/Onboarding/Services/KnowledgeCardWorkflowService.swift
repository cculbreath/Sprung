import Foundation
import SwiftyJSON

/// Service responsible for knowledge card workflow: generation, validation, persistence, and plan item management.
/// Extracted from CoordinatorEventRouter to improve separation of concerns.
@MainActor
final class KnowledgeCardWorkflowService {
    private let ui: OnboardingUIState
    private let state: StateCoordinator
    private let sessionUIState: SessionUIState
    private let toolRouter: ToolHandler
    private let resRefStore: ResRefStore
    private let eventBus: EventCoordinator

    // Pending knowledge card for auto-persist after user confirmation
    private var pendingKnowledgeCard: JSON?

    // Track failed KC agent generations so the coordinator LLM can fall back to manual card creation.
    private var failedKCCards: [(cardId: String, title: String, error: String)] = []

    init(
        ui: OnboardingUIState,
        state: StateCoordinator,
        sessionUIState: SessionUIState,
        toolRouter: ToolHandler,
        resRefStore: ResRefStore,
        eventBus: EventCoordinator
    ) {
        self.ui = ui
        self.state = state
        self.sessionUIState = sessionUIState
        self.toolRouter = toolRouter
        self.resRefStore = resRefStore
        self.eventBus = eventBus
    }

    // MARK: - Pending Card Management

    func hasPendingKnowledgeCard() -> Bool {
        pendingKnowledgeCard != nil
    }

    // MARK: - Event Handlers

    /// Handle "Done with this card" button click
    func handleDoneButtonClicked(itemId: String?) async {
        // Clear batch upload flag - user clicking "Done" means they're done with uploads
        // This is a safety measure in case batch completion didn't fire properly
        if ui.hasBatchUploadInProgress {
            ui.hasBatchUploadInProgress = false
            Logger.info("📦 Cleared batch upload flag on 'Done' button click", category: .ai)
        }

        // Ungate submit_knowledge_card tool
        await state.includeTool(OnboardingToolName.submitKnowledgeCard.rawValue)

        // Send system-generated user message to trigger LLM response
        // Using user message instead of developer message ensures the LLM responds immediately
        // Force toolChoice to ensure the LLM calls submit_knowledge_card
        let itemInfo = itemId ?? "unknown"
        var userMessage = JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = """
            I'm done with the "\(itemInfo)" card. \
            Please generate and submit the knowledge card now.
            """
        await eventBus.publish(.llmEnqueueUserMessage(
            payload: userMessage,
            isSystemGenerated: true,
            toolChoice: OnboardingToolName.submitKnowledgeCard.rawValue
        ))

        Logger.info("✅ Done button handled: tool ungated, user message sent with forced toolChoice for item '\(itemInfo)'", category: .ai)
    }

    /// Handle pending knowledge card submission
    func handleSubmissionPending(card: JSON) {
        pendingKnowledgeCard = card
        Logger.info("📝 Pending knowledge card stored: \(card["title"].stringValue)", category: .ai)
    }

    /// Handle auto-persist request after user confirms
    func handleAutoPersistRequested() async {
        guard let card = pendingKnowledgeCard else {
            Logger.warning("⚠️ Auto-persist requested but no pending card", category: .ai)
            return
        }

        let cardTitle = card["title"].stringValue
        Logger.info("💾 Persisting knowledge card to SwiftData: \(cardTitle)", category: .ai)

        // Persist to SwiftData (ResRef) - single source of truth for knowledge cards
        persistToResRef(card: card)

        // Emit persisted event (for UI updates)
        await eventBus.publish(.knowledgeCardPersisted(card: card))

        // Update plan item status if linked
        if let planItemId = card["plan_item_id"].string {
            await handlePlanItemStatusChange(itemId: planItemId, status: "completed")
        }

        // Clear pending card
        pendingKnowledgeCard = nil

        // Emit success event
        await eventBus.publish(.knowledgeCardAutoPersisted(title: cardTitle))

        // Send LLM message about successful persistence
        var userMessage = JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = """
            Knowledge card confirmed and persisted: "\(cardTitle)".
            The plan item has been marked complete.
            Proceed to the next pending plan item, or call display_knowledge_card_plan to see progress.
            """
        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))

        Logger.info("✅ Knowledge card persisted: \(cardTitle)", category: .ai)
    }

    /// Handle "Generate Cards" button click - ungates dispatch_kc_agents and mandates its use
    func handleGenerateCardsButtonClicked() async {
        Logger.info("🚀 Generate Cards button clicked - ungating dispatch_kc_agents", category: .ai)

        // Ungate dispatch_kc_agents tool
        await state.includeTool(OnboardingToolName.dispatchKCAgents.rawValue)

        // Send system-generated user message with forced toolChoice
        var userMessage = JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = """
            I've reviewed the card assignments and I'm ready to generate the knowledge cards. \
            Please proceed with generating the cards now.
            """
        await eventBus.publish(.llmEnqueueUserMessage(
            payload: userMessage,
            isSystemGenerated: true,
            toolChoice: OnboardingToolName.dispatchKCAgents.rawValue
        ))

        Logger.info("✅ Generate Cards: tool ungated, user message sent with forced toolChoice for dispatch_kc_agents", category: .ai)
    }

    // MARK: - KC Agent Completion Handlers

    /// Handle KC agent failure - surface error to user
    func handleKCAgentFailed(agentId: String, cardId: String, error: String) async {
        Logger.error("❌ KC agent failed: cardId=\(cardId.prefix(8)), error=\(error)", category: .ai)

        // Ensure manual fallback tool is available (subphase bundling must also include it).
        await state.includeTool(OnboardingToolName.submitKnowledgeCard.rawValue)

        // Capture failure details for a single summary message after dispatch completes.
        let planItems = await MainActor.run { ui.knowledgeCardPlan }
        let title = planItems.first(where: { $0.id == cardId })?.title ?? "Unknown card"
        failedKCCards.append((cardId: cardId, title: title, error: error))

        // Surface error to user via the error event (displayed in chat/UI)
        let failureMessage = "Knowledge card generation failed: \(error)"
        await eventBus.publish(.errorOccurred(failureMessage))
    }

    /// After all agents finish, instruct the coordinator LLM to fill gaps manually if needed.
    func handleKCAgentsDispatchCompleted(successCount: Int, failureCount: Int) async {
        guard failureCount > 0 else {
            failedKCCards.removeAll()
            return
        }

        await state.includeTool(OnboardingToolName.submitKnowledgeCard.rawValue)

        let failures = failedKCCards
        failedKCCards.removeAll()

        var lines: [String] = []
        lines.append("Some knowledge card agents failed (\(failureCount) failed, \(successCount) succeeded).")
        if !failures.isEmpty {
            lines.append("")
            lines.append("Failed cards to create manually:")
            for item in failures.prefix(10) {
                lines.append("- \(item.title) (card_id: \(item.cardId))")
            }
        }
        lines.append("")
        lines.append("Please create replacement cards manually using `submit_knowledge_card` (full card object + summary).")
        lines.append("Use `get_context_pack` (optionally with `card_id`) and `list_artifacts/get_artifact` to pull the needed evidence first.")

        var userMessage = JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = lines.joined(separator: "\n")
        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))

        Logger.info("🛟 Manual KC fallback activated: submit_knowledge_card ungated after agent failures", category: .ai)
    }

    /// Handle KC agent completion - auto-present validation UI without LLM tool call
    /// Cards are queued and presented immediately as they complete
    func handleKCAgentCompleted(agentId: String, cardId: String, cardTitle: String) async {
        Logger.info("🎉 KC agent completed: '\(cardTitle)' (cardId: \(cardId.prefix(8)), agentId: \(agentId.prefix(8)))", category: .ai)

        // Enqueue this card for validation
        await sessionUIState.enqueueKCValidation(cardId)

        // Check if validation UI is already showing
        let currentValidation = await sessionUIState.pendingValidationPrompt
        if currentValidation != nil {
            // Another validation is in progress - card is already queued
            Logger.info("📋 KC validation queued (another validation in progress): \(cardTitle)", category: .ai)
            return
        }

        // No active validation - present this card immediately
        await presentNextKCValidation()
    }

    /// Present the next card from the KC validation queue
    private func presentNextKCValidation() async {
        // Dequeue the next card ID
        guard let cardId = await sessionUIState.dequeueNextKCValidation() else {
            Logger.debug("📋 No KC validations in queue", category: .ai)
            return
        }

        // Retrieve the pending card from state
        guard let card = await state.getPendingCard(id: cardId) else {
            Logger.warning("⚠️ KC auto-validation: pending card not found for ID \(cardId.prefix(8))", category: .ai)
            // Try the next card in queue
            if await sessionUIState.hasQueuedKCValidations() {
                await presentNextKCValidation()
            }
            return
        }

        let cardTitle = card["card"]["title"].stringValue

        // Mark as auto-validation (not tool-initiated)
        await sessionUIState.setAutoValidation(true)

        // Store as pending knowledge card for auto-persist
        pendingKnowledgeCard = card

        // Build summary for validation UI
        let wordCount = card["card"]["content"].stringValue.components(separatedBy: .whitespacesAndNewlines).count
        let summary = "Knowledge card for \(cardTitle) (\(wordCount) words)"

        // Create validation prompt
        let prompt = OnboardingValidationPrompt(
            dataType: "knowledge_card",
            payload: card["card"],
            message: summary
        )

        // Emit validation prompt request (will show UI)
        await eventBus.publish(.validationPromptRequested(prompt: prompt))
        Logger.info("🎯 KC auto-validation presented: \(cardTitle)", category: .ai)
    }

    /// Present next KC validation after user completes one (called from UIResponseCoordinator)
    func presentNextKCValidationIfQueued() async {
        if await sessionUIState.hasQueuedKCValidations() {
            await presentNextKCValidation()
        } else {
            // Clear auto-validation flag when queue is empty
            await sessionUIState.setAutoValidation(false)
        }
    }

    /// Handle KC auto-validation approval - persist card and send developer message
    func handleKCAutoValidationApproved() async {
        guard let card = pendingKnowledgeCard else {
            Logger.warning("⚠️ KC auto-validation approved but no pending card", category: .ai)
            await presentNextKCValidationIfQueued()
            return
        }

        let cardData = card["card"]
        let cardTitle = cardData["title"].stringValue
        let cardId = cardData["id"].stringValue

        // Persist to ResRef (SwiftData) - this is the authoritative source for knowledge cards
        // Phase transition validation queries ResRefStore directly
        persistToResRef(card: cardData)

        // Clear pending card
        pendingKnowledgeCard = nil

        // Remove from pending storage
        await state.removePendingCard(id: cardId)

        // Clear validation prompt
        toolRouter.clearValidationPrompt()
        await eventBus.publish(.validationPromptCleared)

        // Send developer message to LLM
        let message = """
        Knowledge card "\(cardTitle)" has been approved and persisted.
        Card ID: \(cardId)
        """
        await eventBus.publish(.llmSendDeveloperMessage(payload: JSON(["text": message])))

        Logger.info("✅ KC auto-validation approved and persisted: \(cardTitle)", category: .ai)

        // Present next card from queue (if any)
        await presentNextKCValidationIfQueued()
    }

    /// Handle KC auto-validation rejection - send developer message with reason
    func handleKCAutoValidationRejected(reason: String) async {
        guard let card = pendingKnowledgeCard else {
            Logger.warning("⚠️ KC auto-validation rejected but no pending card", category: .ai)
            await presentNextKCValidationIfQueued()
            return
        }

        let cardData = card["card"]
        let cardTitle = cardData["title"].stringValue
        let cardId = cardData["id"].stringValue

        // Clear pending card (not persisted)
        pendingKnowledgeCard = nil

        // Remove from pending storage (rejected, won't be resubmitted automatically)
        await state.removePendingCard(id: cardId)

        // Clear validation prompt
        toolRouter.clearValidationPrompt()
        await eventBus.publish(.validationPromptCleared)

        // Send developer message to LLM
        let message = """
        Knowledge card "\(cardTitle)" was rejected by the user.
        Card ID: \(cardId)
        Reason: \(reason)
        You may dispatch another KC agent to regenerate this card if needed.
        """
        await eventBus.publish(.llmSendDeveloperMessage(payload: JSON(["text": message])))

        Logger.info("❌ KC auto-validation rejected: \(cardTitle) - \(reason)", category: .ai)

        // Present next card from queue (if any)
        await presentNextKCValidationIfQueued()
    }

    // MARK: - Plan Item Status

    /// Handle plan item status change request - updates UI state directly
    func handlePlanItemStatusChange(itemId: String, status: String) async {
        // Convert status string to enum
        let planStatus: KnowledgeCardPlanItem.Status
        switch status.lowercased() {
        case "completed":
            planStatus = .completed
        case "in_progress":
            planStatus = .inProgress
        case "skipped":
            planStatus = .skipped
        default:
            planStatus = .pending
        }

        // Update UI state directly (no coordinator needed)
        guard let index = ui.knowledgeCardPlan.firstIndex(where: { $0.id == itemId }) else {
            Logger.warning("⚠️ Could not find plan item \(itemId) to update status", category: .ai)
            return
        }
        let item = ui.knowledgeCardPlan[index]
        ui.knowledgeCardPlan[index] = KnowledgeCardPlanItem(
            id: item.id,
            title: item.title,
            type: item.type,
            description: item.description,
            status: planStatus,
            timelineEntryId: item.timelineEntryId
        )
        Logger.info("📋 Plan item status updated: \(itemId) → \(status)", category: .ai)
    }

    // MARK: - Persistence

    /// Persist knowledge card to SwiftData as a ResRef for use in resume generation
    private func persistToResRef(card: JSON) {
        let title = card["title"].stringValue
        let content = card["content"].stringValue
        let cardType = card["type"].string
        let timePeriod = card["time_period"].string
        let organization = card["organization"].string
        let location = card["location"].string
        let tokenCount = card["token_count"].int

        // Encode sources array as JSON string
        var sourcesJSON: String?
        if let sourcesArray = card["sources"].array, !sourcesArray.isEmpty {
            if let data = try? JSON(sourcesArray).rawData(),
               let jsonString = String(data: data, encoding: .utf8) {
                sourcesJSON = jsonString
            }
        }

        let resRef = ResRef(
            name: title,
            content: content,
            enabledByDefault: true,  // Knowledge cards default to enabled
            cardType: cardType,
            timePeriod: timePeriod,
            organization: organization,
            location: location,
            sourcesJSON: sourcesJSON,
            isFromOnboarding: true,
            tokenCount: tokenCount
        )

        resRefStore.addResRef(resRef)
        Logger.info("✅ Knowledge card persisted to ResRef (SwiftData): \(title) (tokens: \(tokenCount ?? 0))", category: .ai)
    }
}
