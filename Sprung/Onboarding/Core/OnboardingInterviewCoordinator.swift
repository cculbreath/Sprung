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
    var chatTranscriptStore: ChatTranscriptStore { container.chatTranscriptStore }
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

    /// Returns the card merge service for merging document inventories
    var cardMergeService: CardMergeService {
        container.cardMergeService
    }

    /// Returns the LLM facade for AI operations
    var llmFacade: LLMFacade? {
        container.llmFacade
    }

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
        if let session = container.sessionPersistenceHandler.getActiveSession() {
            container.sessionPersistenceHandler.deleteSession(session)
        }
    }

    /// Clear all onboarding data: session, knowledge cards, CoverRefs, ExperienceDefaults, and ApplicantProfile
    /// Used when user chooses "Start Over" to begin fresh
    func clearAllOnboardingData() {
        Logger.info("🗑️ Clearing all onboarding data", category: .ai)
        // Delete session
        deleteCurrentSession()
        // Delete onboarding knowledge cards
        knowledgeCardStore.deleteOnboardingCards()
        // Delete all CoverRefs
        for coverRef in coverRefStore.storedCoverRefs {
            coverRefStore.deleteCoverRef(coverRef)
        }
        Logger.debug("🗑️ Deleted all CoverRefs", category: .ai)
        // Clear ExperienceDefaults
        let defaults = experienceDefaultsStore.currentDefaults()
        defaults.work.removeAll()
        defaults.education.removeAll()
        defaults.volunteer.removeAll()
        defaults.projects.removeAll()
        defaults.skills.removeAll()
        defaults.awards.removeAll()
        defaults.certificates.removeAll()
        defaults.publications.removeAll()
        defaults.languages.removeAll()
        defaults.interests.removeAll()
        defaults.references.removeAll()
        experienceDefaultsStore.save(defaults)
        experienceDefaultsStore.clearCache()
        Logger.debug("🗑️ Cleared ExperienceDefaults", category: .ai)
        // Reset ApplicantProfile to defaults (including photo)
        applicantProfileStore.reset()
        Logger.debug("🗑️ Reset ApplicantProfile", category: .ai)
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
        await container.eventBus.publish(.llmExecuteDeveloperMessage(payload: payload))
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
                await eventBus.publish(.llmSendDeveloperMessage(payload: payload))
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
    func sendDeveloperMessage(title: String, details: [String: String] = [:], toolChoice: String? = nil) async {
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
        await eventBus.publish(.llmSendDeveloperMessage(payload: payload))
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
        await sendDeveloperMessage(
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
        container.artifactRecordStore.archivedArtifacts
    }

    /// Get current session artifacts for UI display (directly from SwiftData).
    func getCurrentSessionArtifacts() -> [ArtifactRecord] {
        guard let session = container.sessionPersistenceHandler.getActiveSession() else { return [] }
        return container.artifactRecordStore.artifacts(for: session)
    }


    /// Promote an archived artifact to the current session.
    /// This makes the artifact available to the LLM and adds it to the current interview.
    func promoteArchivedArtifact(id: String) async {
        guard let session = container.sessionPersistenceHandler.getActiveSession() else {
            Logger.warning("Cannot promote artifact: no active session", category: .ai)
            return
        }

        guard let artifact = container.artifactRecordStore.artifact(byIdString: id) else {
            Logger.warning("Cannot promote artifact: not found in SwiftData: \(id)", category: .ai)
            return
        }

        // Update SwiftData: move artifact to current session
        container.artifactRecordStore.promoteArtifact(artifact, to: session)

        // Convert to JSON for in-memory repository and LLM notification
        let artifactJSON = artifactRecordToJSON(artifact)

        // Add to in-memory artifact list for event-driven components
        await container.artifactRepository.addArtifactRecord(artifactJSON)

        // Emit event to notify LLM and other handlers
        await eventBus.publish(.artifactRecordProduced(record: artifactJSON))

        Logger.info("📦 Promoted archived artifact: \(artifact.filename)", category: .ai)
    }

    /// Permanently delete an archived artifact.
    /// This removes the artifact from SwiftData - it cannot be recovered.
    func deleteArchivedArtifact(id: String) async {
        guard let artifact = container.artifactRecordStore.artifact(byIdString: id) else {
            Logger.warning("Cannot delete archived artifact: not found: \(id)", category: .ai)
            return
        }

        let filename = artifact.filename

        // Delete from SwiftData
        container.artifactRecordStore.deleteArtifact(artifact)

        Logger.info("🗑️ Permanently deleted archived artifact: \(filename)", category: .ai)
    }

    /// Demote an artifact from the current session to archived status.
    /// This removes the artifact from the current interview but keeps it available for future use.
    func demoteArtifact(id: String) async {
        guard let artifact = container.artifactRecordStore.artifact(byIdString: id) else {
            Logger.warning("Cannot demote artifact: not found: \(id)", category: .ai)
            return
        }

        let filename = artifact.filename

        // Demote in SwiftData (removes from session, keeps artifact)
        container.artifactRecordStore.demoteArtifact(artifact)

        // Remove from in-memory current artifacts
        _ = await container.artifactRepository.deleteArtifactRecord(id: id)

        // Notify LLM that artifact was removed from current interview
        await sendDeveloperMessage(
            title: "Artifact Removed from Interview",
            details: [
                "artifact_id": id,
                "filename": filename,
                "action": "The user has removed this artifact from the current interview. It is no longer available for reference in this session, but remains in the archive for future use."
            ]
        )

        Logger.info("📦 Demoted artifact to archive: \(filename)", category: .ai)
    }

    /// Convert ArtifactRecord to JSON format.
    /// Uses metadataJSON as base to preserve all fields (skills, narrative cards, summary, etc.)
    private func artifactRecordToJSON(_ record: ArtifactRecord) -> JSON {
        // Start with the full persisted record (includes skills, narrative cards, metadata, etc.)
        var json: JSON
        if let metadataJSON = record.metadataJSON,
           let data = metadataJSON.data(using: .utf8),
           let fullRecord = try? JSON(data: data) {
            json = fullRecord
        } else {
            json = JSON()
        }
        // Override with canonical SwiftData fields (in case of any discrepancy)
        json["id"].string = record.id.uuidString
        json["source_type"].string = record.sourceType
        json["filename"].string = record.filename
        json["extracted_text"].string = record.extractedContent
        json["source_hash"].string = record.sha256
        json["raw_file_path"].string = record.rawFileRelativePath
        json["plan_item_id"].string = record.planItemId
        json["ingested_at"].string = ISO8601DateFormatter().string(from: record.ingestedAt)
        json["summary"].string = record.summary
        json["brief_description"].string = record.briefDescription
        json["title"].string = record.title
        json["content_type"].string = record.contentType
        json["size_bytes"].int = record.sizeInBytes
        json["has_skills"].bool = record.hasSkills
        json["has_narrative_cards"].bool = record.hasNarrativeCards
        json["skills"].string = record.skillsJSON
        json["narrative_cards"].string = record.narrativeCardsJSON
        return json
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

        // Deactivate document collection UI and clear waiting state
        await MainActor.run {
            ui.isDocumentCollectionActive = false
        }
        await container.sessionUIState.setDocumentCollectionActive(false)

        // Send message to LLM
        await sendChatMessage("I'm done uploading documents. (Note: Some document extractions were cancelled.) Please assess the completeness of my evidence.")

        Logger.debug("✅ Extraction agents cancelled and document upload phase finished", category: .ai)
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

    /// Clear all summaries and card inventories and regenerate them, then trigger merge
    func regenerateCardInventoriesAndMerge() async {
        Logger.debug("🔄 Clearing and regenerating ALL summaries + card inventories...", category: .ai)

        // Get all non-writing-sample artifacts
        let artifactsToProcess = sessionArtifacts.filter { !$0.isWritingSample }

        Logger.debug("📦 Found \(artifactsToProcess.count) artifacts to regenerate", category: .ai)

        guard !artifactsToProcess.isEmpty else {
            Logger.debug("⚠️ No artifacts to process", category: .ai)
            return
        }

        // Clear existing summaries and knowledge extraction first
        for artifact in artifactsToProcess {
            artifact.summary = nil
            artifact.briefDescription = nil
            artifact.skillsJSON = nil
            artifact.narrativeCardsJSON = nil
            Logger.verbose("🗑️ Cleared summary + knowledge for: \(artifact.filename)", category: .ai)
        }

        // Use same concurrency limit as document extraction
        let maxConcurrent = UserDefaults.standard.integer(forKey: "onboardingMaxConcurrentExtractions")
        let concurrencyLimit = maxConcurrent > 0 ? maxConcurrent : 5

        Logger.debug("📦 Processing \(artifactsToProcess.count) artifacts with concurrency limit \(concurrencyLimit)", category: .ai)

        // Capture service reference for use in task group
        let documentProcessingService = container.documentProcessingService

        // Process with limited concurrency using TaskGroup
        await withTaskGroup(of: Void.self) { group in
            var inFlight = 0
            var index = 0

            for artifact in artifactsToProcess {
                // Wait if we've hit the concurrency limit
                if inFlight >= concurrencyLimit {
                    await group.next()
                    inFlight -= 1
                }

                group.addTask {
                    await documentProcessingService.generateSummaryAndKnowledgeExtractionForExistingArtifact(artifact)
                }
                inFlight += 1
                index += 1
                Logger.verbose("📦 Dispatched \(index)/\(artifactsToProcess.count): \(artifact.filename)", category: .ai)
            }

            // Wait for all remaining tasks
            for await _ in group { }
        }

        Logger.debug("✅ All summary + inventory regeneration complete", category: .ai)

        // Trigger the merge
        Logger.debug("🔄 Triggering card merge...", category: .ai)
        await eventBus.publish(.doneWithUploadsClicked)
    }

    /// Selective regeneration based on user choices from RegenOptionsDialog
    /// - Parameters:
    ///   - artifactIds: Set of artifact IDs to process
    ///   - regenerateSummary: Whether to regenerate summaries
    ///   - regenerateSkills: Whether to regenerate skills
    ///   - regenerateNarrativeCards: Whether to regenerate narrative cards
    ///   - dedupeNarratives: Whether to run narrative deduplication after regeneration
    func regenerateSelected(
        artifactIds: Set<String>,
        regenerateSummary: Bool,
        regenerateSkills: Bool,
        regenerateNarrativeCards: Bool,
        dedupeNarratives: Bool = false
    ) async {
        Logger.debug("🔄 Selective regeneration: \(artifactIds.count) artifacts, summary=\(regenerateSummary), skills=\(regenerateSkills), cards=\(regenerateNarrativeCards), dedupe=\(dedupeNarratives)", category: .ai)

        // Get selected artifacts
        let artifactsToProcess = sessionArtifacts.filter { artifactIds.contains($0.idString) }

        guard !artifactsToProcess.isEmpty else {
            Logger.debug("⚠️ No artifacts selected", category: .ai)
            return
        }

        // Build operation description
        var ops: [String] = []
        if regenerateSummary { ops.append("summary") }
        if regenerateSkills { ops.append("skills") }
        if regenerateNarrativeCards { ops.append("cards") }
        let opsDesc = ops.joined(separator: "+")

        // Track the regeneration as an agent
        let agentId = agentActivityTracker.trackAgent(
            type: .documentRegen,
            name: "Regen \(artifactsToProcess.count) docs (\(opsDesc))",
            task: nil as Task<Void, Never>?
        )

        agentActivityTracker.appendTranscript(
            agentId: agentId,
            entryType: .system,
            content: "Starting regeneration",
            details: "Artifacts: \(artifactsToProcess.count), Summary: \(regenerateSummary), Skills: \(regenerateSkills), Cards: \(regenerateNarrativeCards), Dedupe: \(dedupeNarratives)"
        )

        // Clear selected fields first
        for artifact in artifactsToProcess {
            if regenerateSummary {
                artifact.summary = nil
                artifact.briefDescription = nil
            }
            if regenerateSkills {
                artifact.skillsJSON = nil
            }
            if regenerateNarrativeCards {
                artifact.narrativeCardsJSON = nil
            }
            Logger.verbose("🗑️ Cleared selected fields for: \(artifact.filename)", category: .ai)
        }

        // Use same concurrency limit as document extraction
        let maxConcurrent = UserDefaults.standard.integer(forKey: "onboardingMaxConcurrentExtractions")
        let concurrencyLimit = maxConcurrent > 0 ? maxConcurrent : 5

        let documentProcessingService = container.documentProcessingService
        let tracker = agentActivityTracker

        // Track completed count
        let completedCount = Counter()

        // Process with limited concurrency
        await withTaskGroup(of: Void.self) { group in
            var inFlight = 0
            var index = 0

            for artifact in artifactsToProcess {
                if inFlight >= concurrencyLimit {
                    await group.next()
                    inFlight -= 1
                }

                let artifactName = artifact.filename
                let total = artifactsToProcess.count

                group.addTask {
                    // Handle summary
                    if regenerateSummary {
                        await documentProcessingService.generateSummaryForExistingArtifact(artifact)
                    }

                    // Handle skills and narrative cards
                    if regenerateSkills && regenerateNarrativeCards {
                        // Both - use the combined method for efficiency
                        await documentProcessingService.generateKnowledgeExtractionForExistingArtifact(artifact)
                    } else if regenerateSkills {
                        await documentProcessingService.generateSkillsOnlyForExistingArtifact(artifact)
                    } else if regenerateNarrativeCards {
                        await documentProcessingService.generateNarrativeCardsOnlyForExistingArtifact(artifact)
                    }

                    // Track completion
                    let completed = await completedCount.increment()
                    await MainActor.run {
                        tracker.appendTranscript(
                            agentId: agentId,
                            entryType: .toolResult,
                            content: "Completed \(completed)/\(total): \(artifactName)"
                        )
                        tracker.updateStatusMessage(agentId: agentId, message: "Processing \(completed)/\(total)...")
                    }
                }
                inFlight += 1
                index += 1
                Logger.verbose("📦 Dispatched \(index)/\(artifactsToProcess.count): \(artifact.filename)", category: .ai)
            }

            for await _ in group { }
        }

        Logger.debug("✅ Selective regeneration complete", category: .ai)

        agentActivityTracker.appendTranscript(
            agentId: agentId,
            entryType: .system,
            content: "Regeneration complete",
            details: "Processed \(artifactsToProcess.count) artifacts"
        )

        if dedupeNarratives {
            Logger.debug("🔀 Running narrative deduplication...", category: .ai)
            agentActivityTracker.appendTranscript(
                agentId: agentId,
                entryType: .system,
                content: "Running narrative deduplication..."
            )
            await deduplicateNarratives()
        }

        agentActivityTracker.markCompleted(agentId: agentId)
    }

    /// Thread-safe counter for tracking completed operations
    private actor Counter {
        private var value = 0

        func increment() -> Int {
            value += 1
            return value
        }
    }

    /// Run narrative card deduplication manually
    /// Uses LLM to identify and merge duplicate cards across documents
    func deduplicateNarratives() async {
        do {
            let result = try await cardMergeService.getAllNarrativeCardsDeduped()
            Logger.info("✅ Deduplication complete: \(result.cards.count) cards, \(result.mergeLog.count) merges", category: .ai)

            // Clear existing pending cards and add deduplicated ones
            await MainActor.run {
                knowledgeCardStore.deletePendingCards()
                for card in result.cards {
                    card.isFromOnboarding = true
                    card.isPending = true
                }
                knowledgeCardStore.addAll(result.cards)
            }

            // Log merge decisions for debugging
            for entry in result.mergeLog {
                Logger.debug("🔀 \(entry.action.rawValue): \(entry.inputCardIds.joined(separator: " + ")) → \(entry.outputCardId ?? "N/A")", category: .ai)
            }
        } catch {
            Logger.error("❌ Deduplication failed: \(error.localizedDescription)", category: .ai)
        }
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
