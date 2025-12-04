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
    private let resRefStore: ResRefStore
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
        resRefStore: ResRefStore,
        eventBus: EventCoordinator,
        dataStore: InterviewDataStore,
        coordinator: OnboardingInterviewCoordinator
    ) {
        self.ui = ui
        self.state = state
        self.phaseTransitionController = phaseTransitionController
        self.toolRouter = toolRouter
        self.applicantProfileStore = applicantProfileStore
        self.resRefStore = resRefStore
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
        // Log ALL events to track potential blocking (info level for debugging)
        Logger.info("📊 CoordinatorEventRouter: Processing event: \(String(describing: event))", category: .ai)
        switch event {
        case .objectiveStatusChanged(let id, _, let newStatus, _, _, _, _):
            Logger.debug("📊 CoordinatorEventRouter: objectiveStatusChanged received - id=\(id), newStatus=\(newStatus)", category: .ai)
            if id == "applicant_profile" && newStatus == "completed" {
                Logger.info("📊 CoordinatorEventRouter: Dismissing profile summary for applicant_profile completion", category: .ai)
                toolRouter.profileHandler.dismissProfileSummary()
            }
        case .timelineUIUpdateNeeded:
            // Timeline UI updates are now handled by UIStateUpdateHandler via topic-specific stream
            // This provides immediate updates without waiting in the congested streamAll() queue
            break
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
            Logger.info("📊 CoordinatorEventRouter: objectiveStatusRequested - awaiting status for \(id)", category: .ai)
            let status = await state.getObjectiveStatus(id)?.rawValue
            response(status)
            Logger.info("📊 CoordinatorEventRouter: objectiveStatusRequested - completed for \(id)", category: .ai)
        case .phaseTransitionApplied(let phaseName, _):
            await phaseTransitionController.handlePhaseTransition(phaseName)
            if let phase = InterviewPhase(rawValue: phaseName) {
                ui.phase = phase
                Logger.info("📊 CoordinatorEventRouter: UI phase updated to \(phase.rawValue)", category: .ai)
            } else {
                Logger.warning("📊 CoordinatorEventRouter: Could not convert phaseName '\(phaseName)' to InterviewPhase", category: .ai)
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

    /// Handle auto-persist request after user confirms
    private func handleAutoPersistRequested() async {
        guard let card = pendingKnowledgeCard else {
            Logger.warning("⚠️ Auto-persist requested but no pending card", category: .ai)
            return
        }

        let cardTitle = card["title"].stringValue
        Logger.info("💾 Auto-persisting knowledge card: \(cardTitle)", category: .ai)

        do {
            // Persist to data store (JSON file)
            let identifier = try await dataStore.persist(dataType: "knowledge_card", payload: card)
            Logger.info("✅ Knowledge card persisted to InterviewDataStore with identifier: \(identifier)", category: .ai)

            // Persist to SwiftData (ResRef) for use in resume generation
            persistToResRef(card: card)

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

    /// Persist knowledge card to SwiftData as a ResRef for use in resume generation
    private func persistToResRef(card: JSON) {
        let title = card["title"].stringValue
        let content = card["content"].stringValue
        let cardType = card["type"].string
        let timePeriod = card["time_period"].string
        let organization = card["organization"].string
        let location = card["location"].string

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
            isFromOnboarding: true
        )

        resRefStore.addResRef(resRef)
        Logger.info("✅ Knowledge card persisted to ResRef (SwiftData): \(title)", category: .ai)
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
