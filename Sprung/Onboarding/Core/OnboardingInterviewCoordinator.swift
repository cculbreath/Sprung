import Foundation
import Observation
import SwiftyJSON
import SwiftOpenAI
import UniformTypeIdentifiers
@MainActor
@Observable
final class OnboardingInterviewCoordinator {
    // MARK: - Dependency Container
    private let container: OnboardingDependencyContainer
    // MARK: - Public Dependencies (for View access)
    var state: StateCoordinator { container.state }
    var eventBus: EventCoordinator { container.eventBus }
    var toolRouter: ToolHandler { container.toolRouter }
    var wizardTracker: WizardProgressTracker { container.wizardTracker }
    var phaseRegistry: PhaseScriptRegistry { container.phaseRegistry }
    var toolRegistry: ToolRegistry { container.toolRegistry }
    var ui: OnboardingUIState { container.ui }
    var conversationLogStore: ConversationLogStore { container.conversationLogStore }
    // MARK: - Public Sub-Services (Direct Access)
    // Timeline Management
    var timeline: TimelineManagementService { container.timelineManagementService }
    // Extraction Management
    var extraction: ExtractionManagementService { container.extractionManagementService }
    // Phase & Objective Management
    var phases: PhaseTransitionController { container.phaseTransitionController }

    // MARK: - Private Accessors (for internal use)
    // Lifecycle
    private var lifecycleController: InterviewLifecycleController { container.lifecycleController }
    // UI State
    private var uiStateUpdateHandler: UIStateUpdateHandler { container.uiStateUpdateHandler }
    private var uiResponseCoordinator: UIResponseCoordinator { container.uiResponseCoordinator }
    private var coordinatorEventRouter: CoordinatorEventRouter { container.coordinatorEventRouter }
    // Profile Persistence
    private var profilePersistenceHandler: ProfilePersistenceHandler { container.profilePersistenceHandler }
    // Data Stores (used for data existence checks, reset, and view access)
    private var applicantProfileStore: ApplicantProfileStore { container.getApplicantProfileStore() }
    var knowledgeCardStore: KnowledgeCardStore { container.getKnowledgeCardStore() }
    var skillStore: SkillStore { container.getSkillStore() }
    var guidanceStore: InferenceGuidanceStore { container.getGuidanceStore() }
    private var coverRefStore: CoverRefStore { container.getCoverRefStore() }
    private var experienceDefaultsStore: ExperienceDefaultsStore { container.getExperienceDefaultsStore() }
    private var artifactRecordStore: ArtifactRecordStore { container.artifactRecordStore }
    private var sessionPersistenceHandler: SwiftDataSessionPersistenceHandler { container.sessionPersistenceHandler }
    // MARK: - Computed Properties (Read from StateCoordinator)
    var currentPhase: InterviewPhase {
        get async { await state.phase }
    }
    func currentApplicantProfile() -> ApplicantProfile {
        applicantProfileStore.currentProfile()
    }
    var artifacts: OnboardingArtifacts {
        get async { await state.artifacts }
    }

    /// Typed artifacts for the current session (SwiftData models)
    var sessionArtifacts: [ArtifactRecord] {
        guard let session = sessionPersistenceHandler.currentSession else { return [] }
        return artifactRecordStore.artifacts(for: session)
    }

    /// Writing samples from the current session (typed)
    var sessionWritingSamples: [ArtifactRecord] {
        sessionArtifacts.filter { $0.isWritingSample }
    }

    /// All knowledge cards including both onboarding and manually created
    var allKnowledgeCards: [KnowledgeCard] {
        knowledgeCardStore.knowledgeCards
    }

    /// Access to KnowledgeCardStore for CRUD operations on knowledge cards
    func getKnowledgeCardStore() -> KnowledgeCardStore {
        knowledgeCardStore
    }

    /// Sync a knowledge card to the filesystem mirror (for LLM browsing)
    func syncKnowledgeCardToFilesystem(_ card: KnowledgeCard) async {
        await container.phaseTransitionController.updateKnowledgeCardInFilesystem(card)
    }

    // MARK: - Multi-Agent Infrastructure

    /// Agent activity tracker for monitoring parallel agents
    var agentActivityTracker: AgentActivityTracker {
        container.agentActivityTracker
    }

    /// Token usage tracker for monitoring API token consumption
    var tokenUsageTracker: TokenUsageTracker {
        container.tokenUsageTracker
    }

    /// Todo store for LLM task tracking (debug access)
    var todoStore: InterviewTodoStore {
        container.todoStore
    }

    /// Returns the card merge service for merging document inventories
    var cardMergeService: CardMergeService {
        container.cardMergeService
    }

    /// Returns the LLM facade for AI operations
    var llmFacade: LLMFacade? {
        container.llmFacade
    }

    /// Guidance services
    var voiceProfileService: VoiceProfileService { container.voiceProfileService }
    var titleSetService: TitleSetService { container.titleSetService }

    // MARK: - UI State Properties (from ToolRouter)
    var pendingUploadRequests: [OnboardingUploadRequest] {
        toolRouter.pendingUploadRequests
    }
    var pendingChoicePrompt: OnboardingChoicePrompt? {
        toolRouter.pendingChoicePrompt
    }
    var pendingValidationPrompt: OnboardingValidationPrompt? {
        toolRouter.pendingValidationPrompt
    }
    var pendingApplicantProfileRequest: OnboardingApplicantProfileRequest? {
        toolRouter.pendingApplicantProfileRequest
    }
    var pendingApplicantProfileIntake: OnboardingApplicantProfileIntakeState? {
        toolRouter.pendingApplicantProfileIntake
    }
    var pendingApplicantProfileSummary: JSON? {
        toolRouter.pendingApplicantProfileSummary
    }
    var pendingSectionToggleRequest: OnboardingSectionToggleRequest? {
        toolRouter.pendingSectionToggleRequest
    }
    // MARK: - Initialization
    init(
        llmFacade: LLMFacade?,
        documentExtractionService: DocumentExtractionService,
        applicantProfileStore: ApplicantProfileStore,
        knowledgeCardStore: KnowledgeCardStore,
        skillStore: SkillStore,
        coverRefStore: CoverRefStore,
        experienceDefaultsStore: ExperienceDefaultsStore,
        guidanceStore: InferenceGuidanceStore,
        sessionStore: OnboardingSessionStore,
        dataStore: InterviewDataStore,
        preferences: OnboardingPreferences
    ) {
        // Create dependency container with all service wiring
        self.container = OnboardingDependencyContainer(
            llmFacade: llmFacade,
            documentExtractionService: documentExtractionService,
            applicantProfileStore: applicantProfileStore,
            knowledgeCardStore: knowledgeCardStore,
            skillStore: skillStore,
            coverRefStore: coverRefStore,
            experienceDefaultsStore: experienceDefaultsStore,
            guidanceStore: guidanceStore,
            sessionStore: sessionStore,
            dataStore: dataStore,
            preferences: preferences
        )
        // Complete late initialization (components requiring self reference)
        container.completeInitialization(
            coordinator: self,
            onModelAvailabilityIssue: { [weak self] message in
                self?.ui.modelAvailabilityMessage = message
            }
        )
        // Configure lifecycle controller with state update subscriber
        container.lifecycleController.setStateUpdateSubscriber { [weak self] in
            self?.subscribeToStateUpdates()
        }
        Logger.info("🎯 OnboardingInterviewCoordinator initialized with event-driven architecture", category: .ai)
        Task { await subscribeToEvents() }
        Task { await profilePersistenceHandler.start() }

        #if DEBUG
        configureDebugServices()
        #endif
    }
    // MARK: - Event Subscription
    private func subscribeToEvents() async {
        coordinatorEventRouter.subscribeToEvents(lifecycle: lifecycleController)
    }
    // MARK: - State Updates (Delegated to UIStateUpdateHandler)
    private func subscribeToStateUpdates() {
        let handlers = uiStateUpdateHandler.buildStateUpdateHandlers()
        lifecycleController.subscribeToStateUpdates(handlers)
    }
    // MARK: - Interview Lifecycle
    func startInterview(resumeExisting: Bool = false) async -> Bool {
        return await lifecycleController.startInterview(resumeExisting: resumeExisting)
    }

    /// Check if there's an active session that can be resumed
    func hasActiveSession() -> Bool {
        container.sessionPersistenceHandler.hasActiveSession()
    }

    /// Check if there's any existing onboarding data (session, ResRefs, CoverRefs, or ExperienceDefaults)
    /// Used to determine whether to show the resume/start-over prompt
    func hasExistingOnboardingData() -> Bool {
        // Check for active session
        if hasActiveSession() {
            return true
        }
        // Check for onboarding knowledge cards
        let onboardingCards = knowledgeCardStore.knowledgeCards.filter { $0.isFromOnboarding }
        if !onboardingCards.isEmpty {
            return true
        }
        // Check for onboarding skills
        if !skillStore.onboardingSkills.isEmpty {
            return true
        }
        // Check for CoverRefs
        if !coverRefStore.storedCoverRefs.isEmpty {
            return true
        }
        // Check for ExperienceDefaults with actual data
        let defaults = experienceDefaultsStore.currentDefaults()
        let hasExperienceData = !defaults.work.isEmpty ||
            !defaults.education.isEmpty ||
            !defaults.projects.isEmpty ||
            !defaults.skills.isEmpty
        if hasExperienceData {
            return true
        }
        return false
    }

    /// Delete the current SwiftData session (used when starting over)
    func deleteCurrentSession() {
        container.dataResetService.deleteCurrentSession()
    }

    /// Clear all onboarding data: session, knowledge cards, skills, CoverRefs, ExperienceDefaults, and ApplicantProfile
    /// Used when user chooses "Start Over" to begin fresh
    func clearAllOnboardingData() {
        container.dataResetService.clearAllOnboardingData()
    }
    /// Called when user is done with the interview - triggers finalization flow
    func endInterview() async {
        Logger.info("🏁 User clicked 'End Interview' - initiating finalization flow", category: .ai)

        // Mark dossier objective as completed if not already
        await eventBus.publish(.objectiveStatusUpdateRequested(
            id: OnboardingObjectiveId.dossierComplete.rawValue,
            status: "completed",
            source: "user_action",
            notes: "User clicked 'End Interview' button",
            details: nil
        ))

        // Send a system-generated message to trigger ExperienceDefaults generation and finalization
        var userMessage = SwiftyJSON.JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = """
            I'm ready to finish the interview. Please:
            1. Finalize and persist the candidate dossier
            2. Complete any remaining Phase 3 objectives
            3. Call next_phase to complete the interview
            """
        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
    }

    // MARK: - User Action Helpers

    /// Ensures user button actions always succeed by clearing blocking state and auto-completing pending tools.
    /// Call this at the start of any deliberate user action (button clicks, etc.) to guarantee responsiveness.
    /// - Parameter actionDescription: A short description for logging (e.g., "Done with Writing Samples")
    private func ensureUserActionSucceeds(actionDescription: String) async {
        // Clear any waiting state that blocks tools
        let previousWaitingState = await container.sessionUIState.getWaitingState()
        if previousWaitingState != nil {
            await container.sessionUIState.setWaitingState(nil)
            Logger.debug("🔓 '\(actionDescription)' cleared waiting state: \(previousWaitingState?.rawValue ?? "none")", category: .ai)
        }

        // Auto-complete any pending UI tool call - user action means they're ready to proceed
        if let pendingTool = await state.getPendingUIToolCall() {
            Logger.debug("🔓 '\(actionDescription)' auto-completing pending UI tool: \(pendingTool.toolName) (callId: \(pendingTool.callId.prefix(8)))", category: .ai)
            var autoCompleteOutput = JSON()
            autoCompleteOutput["status"].string = "completed"
            autoCompleteOutput["message"].string = "User proceeded via '\(actionDescription)' action"

            // Build and emit the tool response
            var payload = JSON()
            payload["callId"].string = pendingTool.callId
            payload["output"] = autoCompleteOutput
            await eventBus.publish(.llmToolResponseMessage(payload: payload))

            // Clear the pending tool call
            await state.clearPendingUIToolCall()
        }

        // Clear document collection mode if active
        if ui.isDocumentCollectionActive {
            ui.isDocumentCollectionActive = false
            await eventBus.publish(.documentCollectionActiveChanged(false))
            Logger.debug("🔓 '\(actionDescription)' cleared document collection mode", category: .ai)
        }
    }

    /// Called when user clicks "Done with Writing Samples" button
    /// Behavior differs based on phase:
    /// - Phase 1: Marks `writingSamplesCollected` complete and continues interview
    /// - Phase 3: Marks `oneWritingSample` complete and triggers dossier compilation
    func completeWritingSamplesCollection() async {
        let currentPhase = ui.phase
        Logger.info("📝 User marked writing samples collection as complete (phase: \(currentPhase))", category: .ai)

        // Ensure this user action always succeeds - clear blocks and auto-complete pending tools
        await ensureUserActionSucceeds(actionDescription: "Done with Writing Samples")

        if currentPhase == .phase1VoiceContext {
            // Phase 1: Mark the Phase 1 writing samples objective as completed
            await eventBus.publish(.objectiveStatusUpdateRequested(
                id: OnboardingObjectiveId.writingSamplesCollected.rawValue,
                status: "completed",
                source: "user_action",
                notes: "User clicked 'Done with Writing Samples' button in Phase 1",
                details: nil
            ))

            // Send a system-tagged message (not chatbox) to indicate app state change
            // Using <system> tags tells Claude this is an app notification, not user speech
            var userMessage = SwiftyJSON.JSON()
            userMessage["role"].string = "user"
            userMessage["content"].string = """
                <system>User clicked 'Done with Writing Samples'. \
                The upload UI has been dismissed. Continue with the interview.</system>
                """
            await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
        } else {
            // Phase 3: Mark the Phase 3 writing samples objective as completed
            await eventBus.publish(.objectiveStatusUpdateRequested(
                id: OnboardingObjectiveId.oneWritingSample.rawValue,
                status: "completed",
                source: "user_action",
                notes: "User clicked 'Done with Writing Samples' button in Phase 3",
                details: nil
            ))

            // Send a system-tagged message to trigger dossier compilation
            var userMessage = SwiftyJSON.JSON()
            userMessage["role"].string = "user"
            userMessage["content"].string = """
                <system>User clicked 'Done with Writing Samples'. \
                The upload UI has been dismissed. Proceed to compile the candidate dossier.</system>
                """
            await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
        }
    }

    /// Called when user clicks "Skip" button in Phase 1 writing sample collection
    /// Marks the writing samples objective complete (even with no samples) and continues flow
    func skipWritingSamplesCollection() async {
        Logger.info("📝 User skipped writing samples collection", category: .ai)

        // Ensure this user action always succeeds - clear blocks and auto-complete pending tools
        await ensureUserActionSucceeds(actionDescription: "Skip Writing Samples")

        // Mark the writing samples objective as completed (skipped is still complete)
        await eventBus.publish(.objectiveStatusUpdateRequested(
            id: OnboardingObjectiveId.writingSamplesCollected.rawValue,
            status: "completed",
            source: "user_action",
            notes: "User chose to skip writing samples",
            details: nil
        ))

        // Send a system-generated user message to inform the LLM
        var userMessage = SwiftyJSON.JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = """
            I don't have writing samples available right now. \
            Please continue with the interview - we can develop my voice through conversation.
            """
        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
    }

    /// Notify the LLM that title sets have been curated.
    func notifyTitleSetsCurated() async {
        var userMessage = SwiftyJSON.JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = """
            <system>User saved identity title sets. Proceed to generate experience defaults.</system>
            """
        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
    }

    // MARK: - Evidence Handling
    func handleEvidenceUpload(url: URL, requirementId: String) async {
        await container.artifactIngestionCoordinator.handleEvidenceUpload(url: url, requirementId: requirementId)
    }
    // MARK: - Objective Management
    func updateObjectiveStatus(
        objectiveId: String,
        status: String,
        notes: String? = nil,
        details: [String: String]? = nil
    ) async throws -> JSON {
        await eventBus.publish(.objectiveStatusUpdateRequested(
            id: objectiveId,
            status: status.lowercased(),
            source: "tool",
            notes: notes,
            details: details
        ))
        var result = JSON()
        result["status"].string = "completed"
        result["success"].boolValue = true
        result["objective_id"].stringValue = objectiveId
        result["new_status"].stringValue = status.lowercased()
        return result
    }
    // MARK: - Timeline Management
    func applyUserTimelineUpdate(cards: [TimelineCard], meta: JSON?, diff: TimelineDiff) async {
        await uiResponseCoordinator.applyUserTimelineUpdate(cards: cards, meta: meta, diff: diff)
    }

    /// Delete a timeline card initiated from the UI (immediately syncs to coordinator state)
    /// This ensures the deletion persists even if the LLM updates other cards before user saves
    func deleteTimelineCardFromUI(id: String) async {
        // Remove from the coordinator's skeleton timeline cache
        if var timeline = ui.skeletonTimeline {
            var experiences = timeline["experiences"].arrayValue
            experiences.removeAll { $0["id"].stringValue == id }
            timeline["experiences"] = JSON(experiences)
            ui.skeletonTimeline = timeline
            // Don't increment token here - we don't want to trigger a reload that would fight with the UI
            Logger.debug("🗑️ UI deletion synced: removed card \(id) from coordinator cache", category: .ai)
        }
        // Also emit the event so StateCoordinator updates its state
        // Pass fromUI: true so CoordinatorEventRouter doesn't re-increment the UI token
        await eventBus.publish(.timelineCardDeleted(id: id, fromUI: true))
    }
    // MARK: - Artifact Queries

    /// List summaries of all artifacts.
    func listArtifactSummaries() async -> [JSON] {
        await state.listArtifactSummaries()
    }

    /// Get a specific artifact record by ID.
    func getArtifactRecord(id: String) async -> JSON? {
        await state.getArtifactRecord(id: id)
    }

    /// Request an update to artifact metadata.
    func requestMetadataUpdate(artifactId: String, updates: JSON) async {
        await eventBus.publish(.artifactMetadataUpdateRequested(artifactId: artifactId, updates: updates))
    }

    /// Cancel an upload request.
    func cancelUploadRequest(id: UUID) async {
        await eventBus.publish(.uploadRequestCancelled(id: id))
    }

    // MARK: - Artifact Ingestion (Git Repos, Documents)
    // Uses ArtifactIngestionCoordinator for unified ingestion pipeline

    /// Start git repository analysis using the async ingestion pipeline
    func startGitRepoAnalysis(_ repoURL: URL) async {
        Logger.info("🔬 Starting git repo analysis: \(repoURL.path)", category: .ai)
        await container.artifactIngestionCoordinator.ingestGitRepository(
            repoURL: repoURL,
            planItemId: nil
        )
    }

    /// Fetch URL content and create artifact via agent web search
    func fetchURLForArtifact(_ urlString: String) async {
        Logger.info("🌐 Requesting URL fetch: \(urlString)", category: .ai)
        var payload = JSON()
        payload["text"].string = """
            The user wants to add content from this URL: \(urlString)
            Use web_search to fetch the content, then use create_web_artifact
            to save it as an artifact for document collection.
            """
        await container.eventBus.publish(.llmExecuteCoordinatorMessage(payload: payload))
    }

    // MARK: - Tool Management

    func presentUploadRequest(_ request: OnboardingUploadRequest) {
        Task {
            await eventBus.publish(.uploadRequestPresented(request: request))
        }
    }

    func completeUpload(id: UUID, fileURLs: [URL]) async -> JSON? {
        let result = await toolRouter.completeUpload(id: id, fileURLs: fileURLs)
        Task {
            await eventBus.publish(.uploadRequestCancelled(id: id))
        }
        return result
    }

    func skipUpload(id: UUID) async -> JSON? {
        let result = await toolRouter.skipUpload(id: id)
        Task {
            await eventBus.publish(.uploadRequestCancelled(id: id))
        }
        return result
    }

    func submitValidationResponse(
        status: String,
        updatedData: JSON?,
        changes: JSON?,
        notes: String?
    ) async -> JSON? {
        let pendingValidation = toolRouter.pendingValidationPrompt

        // Emit knowledge card persisted event for in-memory tracking
        if let validation = pendingValidation,
           validation.dataType == "knowledge_card",
           let data = updatedData,
           data != .null,
           ["approved", "modified"].contains(status.lowercased()) {
            await eventBus.publish(.knowledgeCardPersisted(card: data))
        }

        let result = toolRouter.submitValidationResponse(
            status: status,
            updatedData: updatedData,
            changes: changes,
            notes: notes
        )

        if result != nil {
            Task {
                await eventBus.publish(.validationPromptCleared)
            }
            // Mark skeleton_timeline objective as complete when user confirms validation
            if let validation = pendingValidation,
               validation.dataType == "skeleton_timeline",
               ["confirmed", "confirmed_with_changes", "approved", "modified"].contains(status.lowercased()) {
                await eventBus.publish(.objectiveStatusUpdateRequested(
                    id: OnboardingObjectiveId.skeletonTimelineComplete.rawValue,
                    status: "completed",
                    source: "ui_timeline_validated",
                    notes: "Timeline validated by user",
                    details: nil
                ))
                Logger.debug("✅ skeleton_timeline_complete objective marked complete after validation", category: .ai)

                // Force configure_enabled_sections as next step (instead of directly ungating next_phase)
                // next_phase will be ungated when enabledSections objective completes
                var payload = JSON()
                payload["text"].string = """
                    Timeline approved. Now configure which resume sections to include. \
                    Call configure_enabled_sections with recommendations based on user's background.
                    """
                payload["toolChoice"].string = OnboardingToolName.configureEnabledSections.rawValue
                await eventBus.publish(.llmSendCoordinatorMessage(payload: payload))
                Logger.info("🎯 Forcing configure_enabled_sections after timeline validation", category: .ai)
            }
        }
        return result
    }

    // MARK: - Applicant Profile Intake Facade Methods

    func beginProfileUpload() {
        let request = toolRouter.beginApplicantProfileUpload()
        presentUploadRequest(request)
    }

    func beginProfileURLEntry() {
        toolRouter.beginApplicantProfileURL()
    }

    func beginProfileContactsFetch() {
        toolRouter.beginApplicantProfileContactsFetch()
    }

    func beginProfileManualEntry() {
        toolRouter.beginApplicantProfileManualEntry()
    }

    func resetProfileIntakeToOptions() {
        toolRouter.resetApplicantProfileIntakeToOptions()
    }
    func submitProfileDraft(draft: ApplicantProfileDraft, source: OnboardingApplicantProfileIntakeState.Source) async {
        await uiResponseCoordinator.submitProfileDraft(draft: draft, source: source)
    }
    func submitProfileURL(_ urlString: String) async {
        await uiResponseCoordinator.submitProfileURL(urlString)
    }
    // MARK: - Phase Advance
    /// Directly advance to the next phase from UI button click (bypasses LLM)
    func advanceToNextPhaseFromUI() async {
        let currentPhase = ui.phase

        // Determine next phase and its start tool
        let nextPhase: InterviewPhase?
        switch currentPhase {
        case .phase1VoiceContext:
            nextPhase = .phase2CareerStory
        case .phase2CareerStory:
            nextPhase = .phase3EvidenceCollection
        case .phase3EvidenceCollection:
            nextPhase = .phase4StrategicSynthesis
        case .phase4StrategicSynthesis:
            nextPhase = .complete
        case .complete:
            nextPhase = nil
        }

        guard let nextPhase else {
            Logger.warning("Cannot advance from \(currentPhase.rawValue) - no next phase", category: .ai)
            return
        }

        Logger.info("🚀 Phase advance triggered from UI: \(currentPhase.rawValue) → \(nextPhase.rawValue)", category: .ai)

        // Trigger the phase transition directly
        await timeline.requestPhaseTransition(
            from: currentPhase.rawValue,
            to: nextPhase.rawValue,
            reason: "User clicked advance button"
        )

        // Send a synthetic message to notify LLM of the phase change
        var payload = JSON()
        if nextPhase == .complete {
            payload["text"].string = "<system>User has completed the interview.</system>"
        } else {
            payload["text"].string = """
                <system>User has advanced to \(nextPhase.rawValue). \
                Continue the interview in the new phase.</system>
                """
        }
        await eventBus.publish(.llmSendUserMessage(payload: payload, isSystemGenerated: true))
    }

    /// Legacy: Request phase advance by asking LLM (use advanceToNextPhaseFromUI instead)
    func requestPhaseAdvanceFromUI() async {
        // Now just calls the direct method
        await advanceToNextPhaseFromUI()
    }
    // MARK: - UI Response Handling (Send User Messages)
    func submitChoiceSelection(_ selectionIds: [String]) async {
        await uiResponseCoordinator.submitChoiceSelection(selectionIds)
    }
    func submitChoiceSelectionWithOther(_ otherText: String) async {
        await uiResponseCoordinator.submitChoiceSelectionWithOther(otherText)
    }
    func cancelChoiceSelection() async {
        await uiResponseCoordinator.cancelChoiceSelection()
    }
    func completeUploadAndResume(id: UUID, fileURLs: [URL]) async {
        await uiResponseCoordinator.completeUploadAndResume(id: id, fileURLs: fileURLs, coordinator: self)
    }
    func skipUploadAndResume(id: UUID) async {
        await uiResponseCoordinator.skipUploadAndResume(id: id, coordinator: self)
    }

    /// Uploads files directly (from persistent drop zone, no pending request needed)
    func uploadFilesDirectly(_ fileURLs: [URL]) async {
        await uiResponseCoordinator.uploadFilesDirectly(fileURLs)
    }

    /// Uploads writing samples for Phase 3 with verbatim transcription
    func uploadWritingSamples(_ fileURLs: [URL]) async {
        await uiResponseCoordinator.uploadWritingSamples(fileURLs)
    }
    func submitValidationAndResume(
        status: String,
        updatedData: JSON?,
        changes: JSON?,
        notes: String?
    ) async {
        await uiResponseCoordinator.submitValidationAndResume(
            status: status,
            updatedData: updatedData,
            changes: changes,
            notes: notes,
            coordinator: self
        )
    }
    func confirmApplicantProfile(draft: ApplicantProfileDraft) async {
        await uiResponseCoordinator.confirmApplicantProfile(draft: draft)
    }
    func rejectApplicantProfile(reason: String) async {
        await uiResponseCoordinator.rejectApplicantProfile(reason: reason)
    }
    func confirmSectionToggle(enabled: [String], customFields: [CustomFieldDefinition] = []) async {
        await uiResponseCoordinator.confirmSectionToggle(enabled: enabled, customFields: customFields)
    }
    func rejectSectionToggle(reason: String) async {
        await uiResponseCoordinator.rejectSectionToggle(reason: reason)
    }
    func clearValidationPromptAndNotifyLLM(message: String) async {
        await uiResponseCoordinator.clearValidationPromptAndNotifyLLM(message: message)
    }

    /// Called when user clicks "Done with Timeline" in the editor.
    /// Closes the editor and forces the LLM to call submit_for_validation.
    func completeTimelineEditingAndRequestValidation() async {
        await uiResponseCoordinator.completeTimelineEditingAndRequestValidation()
    }

    /// Returns the current experience defaults as JSON for validation UI.
    /// Used by SubmitForValidationTool when validation_type="experience_defaults".
    func currentExperienceDefaultsForValidation() async -> JSON {
        let draft = experienceDefaultsStore.loadDraft()
        guard let data = try? JSONEncoder().encode(draft),
              let obj = try? JSONSerialization.jsonObject(with: data) else {
            Logger.warning("⚠️ Failed to encode ExperienceDefaultsDraft for validation", category: .ai)
            return JSON()
        }
        return JSON(obj)
    }
    func sendChatMessage(_ text: String) async {
        await uiResponseCoordinator.sendChatMessage(text)
    }
    func sendCoordinatorMessage(title: String, details: [String: String] = [:], toolChoice: String? = nil) async {
        var payload = JSON()
        payload["title"].string = title
        var detailsJSON = JSON()
        for (key, value) in details {
            detailsJSON[key].string = value
        }
        payload["details"] = detailsJSON
        if let toolChoice = toolChoice {
            payload["toolChoice"].string = toolChoice
        }
        await eventBus.publish(.llmSendCoordinatorMessage(payload: payload))
    }

    /// Delete an artifact record and notify the LLM via developer message.
    /// Called when user deletes an artifact from the Artifacts tab.
    func deleteArtifactRecord(id: String) async {
        // Find the artifact in SwiftData
        guard let artifact = container.artifactRecordStore.artifact(byIdString: id) else {
            Logger.warning("Failed to delete artifact: \(id) - not found", category: .ai)
            return
        }

        let filename = artifact.filename
        let title = artifact.title ?? filename

        // Delete from SwiftData
        container.artifactRecordStore.deleteArtifact(artifact)

        // Also delete from in-memory repository (for event-driven components)
        _ = await state.deleteArtifactRecord(id: id)

        // Send developer message to notify LLM
        await sendCoordinatorMessage(
            title: "Artifact Deleted by User",
            details: [
                "artifact_id": id,
                "filename": filename,
                "title": title,
                "action": "The user has deleted this artifact from the Artifacts tab. It is no longer available for reference."
            ]
        )

        Logger.info("🗑️ Artifact deleted: \(filename)", category: .ai)
    }

    // MARK: - Archived Artifacts Management

    /// Get archived artifacts for UI display (directly from SwiftData).
    func getArchivedArtifacts() -> [ArtifactRecord] {
        container.artifactArchiveManager.archivedArtifacts
    }

    /// Get current session artifacts for UI display (directly from SwiftData).
    func getCurrentSessionArtifacts() -> [ArtifactRecord] {
        container.artifactArchiveManager.currentSessionArtifacts()
    }

    /// Promote multiple archived artifacts to the current session as a batch.
    func promoteArchivedArtifacts(ids: [String]) async {
        await container.artifactArchiveManager.promoteArchivedArtifacts(ids: ids)
    }

    /// Promote a single archived artifact to the current session.
    func promoteArchivedArtifact(id: String) async {
        await container.artifactArchiveManager.promoteArchivedArtifact(id: id)
    }

    /// Permanently delete an archived artifact.
    func deleteArchivedArtifact(id: String) async {
        container.artifactArchiveManager.deleteArchivedArtifact(id: id)
    }

    /// Demote an artifact from the current session to archived status.
    func demoteArtifact(id: String) async {
        let result = await container.artifactArchiveManager.demoteArtifact(id: id)

        // Notify LLM that artifact was removed from current interview
        if result.success {
            await sendCoordinatorMessage(
                title: "Artifact Removed from Interview",
                details: [
                    "artifact_id": result.artifactId,
                    "filename": result.filename,
                    "action": "The user has removed this artifact from the current interview. It is no longer available for reference in this session, but remains in the archive for future use."
                ]
            )
        }
    }

    /// Cancel all active LLM streams and ingestion tasks.
    /// Called when user clicks the Stop button.
    func requestCancelLLM() async {
        Logger.info("🛑 Cancel requested - stopping all streams and ingestion", category: .ai)

        // Cancel LLM streaming
        await uiResponseCoordinator.requestCancelLLM()

        // Cancel any document/git ingestion in progress
        await container.artifactIngestionCoordinator.cancelAllIngestion()

        // Ensure processing state is cleared
        await eventBus.publish(.processingStateChanged(false))

        Logger.info("✅ All streams and ingestion cancelled", category: .ai)
    }

    /// Cancel extraction agents and finish the document upload phase.
    /// Called when user chooses to cancel running agents from the alert dialog.
    func cancelExtractionAgentsAndFinishUploads() async {
        Logger.debug("🛑 Cancelling extraction agents and finishing uploads", category: .ai)

        // Cancel any document/git ingestion in progress
        await container.artifactIngestionCoordinator.cancelAllIngestion()

        // Clear extraction-related UI state
        await MainActor.run {
            ui.hasBatchUploadInProgress = false
            ui.isExtractionInProgress = false
            ui.extractionStatusMessage = nil
        }
        await eventBus.publish(.pendingExtractionUpdated(nil, statusMessage: nil))
        await eventBus.publish(.processingStateChanged(false))
        // Force batch completion so pending artifacts are sent
        await eventBus.publish(.batchUploadCompleted)

        Logger.debug("✅ Extraction agents cancelled and document upload phase finished", category: .ai)

        // Trigger the merge (same as clicking "Done with Uploads" without active agents)
        await finishUploadsAndMergeCards()
    }

    /// Activate document collection UI and gate all tools until user clicks "Done with Uploads"
    func activateDocumentCollection() async {
        await MainActor.run {
            ui.isDocumentCollectionActive = true
        }
        await container.sessionUIState.setDocumentCollectionActive(true)
        Logger.debug("📂 Document collection activated - tools gated until 'Done with Uploads'", category: .ai)
    }

    /// Finish uploads and trigger card merge via event.
    /// Called when user clicks "Done with Uploads" button.
    func finishUploadsAndMergeCards() async {
        Logger.debug("📋 User finished uploads - emitting doneWithUploadsClicked event", category: .ai)

        // Show immediate UI feedback before any async work
        ui.isMergingCards = true
        ui.isDocumentCollectionActive = false

        // Ensure this user action always succeeds - clear blocks and auto-complete pending tools
        await ensureUserActionSucceeds(actionDescription: "Done with Uploads")

        await eventBus.publish(.doneWithUploadsClicked)
    }

    // MARK: - Data Store Management
    func clearArtifacts() {
        lifecycleController.clearArtifacts()
    }
    func resetStore() async {
        await lifecycleController.resetStore()
    }
    // MARK: - Utility
    func clearModelAvailabilityMessage() {
        ui.modelAvailabilityMessage = nil
    }
    func transcriptExportString() -> String {
        ChatTranscriptFormatter.format(messages: ui.messages)
    }
    #if DEBUG
    // MARK: - Debug Event Diagnostics
    func getRecentEvents(count: Int = 10) async -> [OnboardingEvent] {
        await eventBus.getRecentEvents(count: count)
    }
    func getEventMetrics() async -> EventCoordinator.EventMetrics {
        await eventBus.getMetrics()
    }
    func clearEventHistory() async {
        await eventBus.clearHistory()
    }

    /// Configure the debug regeneration service with session artifacts provider
    func configureDebugServices() {
        container.debugRegenerationService.setSessionArtifactsProvider { [weak self] in
            self?.sessionArtifacts ?? []
        }
    }

    /// Clear all summaries and card inventories and regenerate them, then trigger merge
    func regenerateCardInventoriesAndMerge() async {
        await container.debugRegenerationService.regenerateCardInventoriesAndMerge()
    }

    /// Selective regeneration based on user choices from RegenOptionsDialog
    func regenerateSelected(
        artifactIds: Set<String>,
        regenerateSummary: Bool,
        regenerateSkills: Bool,
        regenerateNarrativeCards: Bool,
        dedupeNarratives: Bool = false
    ) async {
        await container.debugRegenerationService.regenerateSelected(
            artifactIds: artifactIds,
            regenerateSummary: regenerateSummary,
            regenerateSkills: regenerateSkills,
            regenerateNarrativeCards: regenerateNarrativeCards,
            dedupeNarratives: dedupeNarratives
        )
    }

    /// Run narrative card deduplication manually
    func deduplicateNarratives() async {
        await container.debugRegenerationService.deduplicateNarratives()
    }

    func resetAllOnboardingData() async {
        Logger.info("🗑️ Resetting all onboarding data", category: .ai)
        // Delete SwiftData session
        deleteCurrentSession()
        Logger.verbose("✅ SwiftData session deleted", category: .ai)
        await MainActor.run {
            // Delete onboarding knowledge cards
            knowledgeCardStore.deleteOnboardingCards()
            Logger.verbose("✅ Onboarding knowledge cards deleted", category: .ai)

            let profile = applicantProfileStore.currentProfile()
            profile.name = "John Doe"
            profile.email = "applicant@example.com"
            profile.phone = "(555) 123-4567"
            profile.address = "123 Main Street"
            profile.city = "Austin"
            profile.state = "Texas"
            profile.zip = "78701"
            profile.websites = "example.com"
            profile.pictureData = nil
            profile.pictureMimeType = nil
            profile.profiles.removeAll()
            applicantProfileStore.save(profile)
            applicantProfileStore.clearCache()
            Logger.info("✅ ApplicantProfile reset and photo removed", category: .ai)
        }
        clearArtifacts()
        Logger.info("✅ Upload artifacts cleared", category: .ai)
        let uploadsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Sprung")
            .appendingPathComponent("Onboarding")
            .appendingPathComponent("Uploads")
        if FileManager.default.fileExists(atPath: uploadsDir.path) {
            do {
                let files = try FileManager.default.contentsOfDirectory(at: uploadsDir, includingPropertiesForKeys: nil)
                for file in files {
                    try FileManager.default.removeItem(at: file)
                }
                Logger.info("✅ Deleted \(files.count) uploaded files from storage", category: .ai)
            } catch {
                Logger.error("❌ Failed to delete uploaded files: \(error.localizedDescription)", category: .ai)
            }
        }
        await resetStore()
        Logger.info("✅ Interview state reset", category: .ai)
        Logger.info("🎉 All onboarding data has been reset", category: .ai)
    }
    #endif
}
