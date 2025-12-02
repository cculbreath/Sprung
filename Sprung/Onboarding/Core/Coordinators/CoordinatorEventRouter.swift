import Foundation
import SwiftyJSON
/// Router responsible for subscribing to and routing coordinator-level events.
/// This component centralizes the event handling logic that was previously in `OnboardingInterviewCoordinator`.
@MainActor
final class CoordinatorEventRouter {
    private let ui: OnboardingUIState
    private let state: StateCoordinator
    private let phaseTransitionController: PhaseTransitionController
    private let toolRouter: ToolHandler
    private let applicantProfileStore: ApplicantProfileStore
    private let eventBus: EventCoordinator
    private let dataStore: InterviewDataStore
    // Weak reference to the parent coordinator to delegate specific actions back if needed
    // In a pure event architecture, this should be minimized, but useful for transition
    private weak var coordinator: OnboardingInterviewCoordinator?

    // Pending knowledge card for auto-persist after user confirmation
    private var pendingKnowledgeCard: JSON?

    init(
        ui: OnboardingUIState,
        state: StateCoordinator,
        phaseTransitionController: PhaseTransitionController,
        toolRouter: ToolHandler,
        applicantProfileStore: ApplicantProfileStore,
        eventBus: EventCoordinator,
        dataStore: InterviewDataStore,
        coordinator: OnboardingInterviewCoordinator
    ) {
        self.ui = ui
        self.state = state
        self.phaseTransitionController = phaseTransitionController
        self.toolRouter = toolRouter
        self.applicantProfileStore = applicantProfileStore
        self.eventBus = eventBus
        self.dataStore = dataStore
        self.coordinator = coordinator
    }

    // MARK: - Pending Card Management
    func hasPendingKnowledgeCard() -> Bool {
        pendingKnowledgeCard != nil
    }
    func subscribeToEvents(lifecycle: InterviewLifecycleController) {
        lifecycle.subscribeToEvents { [weak self] event in
            await self?.handleEvent(event)
        }
    }
    private func handleEvent(_ event: OnboardingEvent) async {
        switch event {
        case .objectiveStatusChanged(let id, _, let newStatus, _, _, _, _):
            if id == "applicant_profile" && newStatus == "completed" {
                toolRouter.profileHandler.dismissProfileSummary()
            }
        case .timelineCardCreated, .timelineCardUpdated,
             .timelineCardDeleted, .timelineCardsReordered, .skeletonTimelineReplaced:
            let timeline = await state.artifacts.skeletonTimeline
            ui.updateTimeline(timeline)
        case .artifactRecordPersisted:
            break
        case .processingStateChanged:
            break
        case .streamingMessageBegan, .streamingMessageUpdated, .streamingMessageFinalized:
            break
        case .llmReasoningSummaryDelta, .llmReasoningSummaryComplete:
            break
        case .streamingStatusUpdated:
            break
        case .waitingStateChanged:
            break
        case .errorOccurred(let error):
            Logger.error("Interview error: \(error)", category: .ai)
            // Errors are now displayed via spinner status message, not popup alerts
        case .llmUserMessageFailed(let messageId, let originalText, let error):
            // Handle failed message: remove from transcript and prepare for input restoration
            ui.handleMessageFailure(messageId: messageId, originalText: originalText, error: error)
        // MARK: - Evidence & Draft Events (Phase 2)
        case .evidenceRequirementAdded(let req):
            ui.evidenceRequirements.append(req)
        case .evidenceRequirementUpdated(let req):
            if let index = ui.evidenceRequirements.firstIndex(where: { $0.id == req.id }) {
                ui.evidenceRequirements[index] = req
            }
        case .evidenceRequirementRemoved(let id):
            ui.evidenceRequirements.removeAll { $0.id == id }
        case .draftKnowledgeCardProduced(let draft):
            ui.drafts.append(draft)
        case .draftKnowledgeCardUpdated(let draft):
            if let index = ui.drafts.firstIndex(where: { $0.id == draft.id }) {
                ui.drafts[index] = draft
            }
        case .draftKnowledgeCardRemoved(let id):
            ui.drafts.removeAll { $0.id == id }
        case .applicantProfileStored:
            // Handled by ProfilePersistenceHandler
            break
        case .skeletonTimelineStored, .enabledSectionsUpdated:
            break
        case .toolCallRequested:
            break
        case .toolCallCompleted:
            break
        case .objectiveStatusRequested(let id, let response):
            let status = await state.getObjectiveStatus(id)?.rawValue
            response(status)
        case .phaseTransitionApplied(let phaseName, _):
            await phaseTransitionController.handlePhaseTransition(phaseName)
            if let phase = InterviewPhase(rawValue: phaseName) {
                ui.phase = phase
            }

        // MARK: - Knowledge Card Workflow Events
        case .knowledgeCardDoneButtonClicked(let itemId):
            await handleDoneButtonClicked(itemId: itemId)

        case .knowledgeCardSubmissionPending(let card):
            pendingKnowledgeCard = card
            Logger.info("📝 Pending knowledge card stored: \(card["title"].stringValue)", category: .ai)

        case .knowledgeCardAutoPersistRequested:
            await handleAutoPersistRequested()

        case .planItemStatusChangeRequested(let itemId, let status):
            await handlePlanItemStatusChange(itemId: itemId, status: status)

        // All other events are handled elsewhere or don't need handling here
        default:
            break
        }
    }

    // MARK: - Knowledge Card Event Handlers

    /// Handle "Done with this card" button click
    private func handleDoneButtonClicked(itemId: String?) async {
        guard let coordinator = coordinator else {
            Logger.error("❌ CoordinatorEventRouter: Coordinator not set", category: .ai)
            return
        }

        // Ungate submit_knowledge_card tool
        await state.includeTool(OnboardingToolName.submitKnowledgeCard.rawValue)

        // Send developer message to force tool call
        let title = """
            User clicked "Done with this card" for item "\(itemId ?? "unknown")". \
            submit_knowledge_card is now ENABLED. \
            Generate the knowledge card NOW by calling submit_knowledge_card with the card JSON and summary.
            """
        let details: [String: String] = itemId != nil ? ["item_id": itemId!, "action": "generate_card"] : ["action": "generate_card"]

        await coordinator.sendDeveloperMessage(
            title: title,
            details: details,
            toolChoice: OnboardingToolName.submitKnowledgeCard.rawValue
        )

        Logger.info("✅ Done button handled: tool ungated, developer message sent", category: .ai)
    }

    /// Handle auto-persist request after user confirms
    private func handleAutoPersistRequested() async {
        guard let card = pendingKnowledgeCard else {
            Logger.warning("⚠️ Auto-persist requested but no pending card", category: .ai)
            return
        }

        let cardTitle = card["title"].stringValue
        Logger.info("💾 Auto-persisting knowledge card: \(cardTitle)", category: .ai)

        do {
            // Persist to data store
            let identifier = try await dataStore.persist(dataType: "knowledge_card", payload: card)
            Logger.info("✅ Knowledge card persisted with identifier: \(identifier)", category: .ai)

            // Emit persisted event (StateCoordinator will update artifact repository)
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

            Logger.info("✅ Knowledge card auto-persist complete: \(cardTitle)", category: .ai)
        } catch {
            Logger.error("❌ Failed to auto-persist knowledge card: \(error)", category: .ai)
        }
    }

    /// Handle plan item status change request
    private func handlePlanItemStatusChange(itemId: String, status: String) async {
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

        coordinator?.updatePlanItemStatus(itemId: itemId, status: planStatus)
        Logger.info("📋 Plan item status updated: \(itemId) → \(status)", category: .ai)
    }
}
