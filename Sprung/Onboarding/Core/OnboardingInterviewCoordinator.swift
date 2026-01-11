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
    var uiToolContinuationManager: UIToolContinuationManager { container.uiToolContinuationManager }
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

    // MARK: - User Action Queue Infrastructure

    /// User action queue for boundary-safe message delivery (exposed for UI)
    var userActionQueue: UserActionQueue { container.userActionQueue }

    /// Drain gate for controlling queue processing (exposed for status bar UI)
    var drainGate: DrainGate { container.drainGate }

    /// Queue drain coordinator for processing queued actions
    private var queueDrainCoordinator: QueueDrainCoordinator { container.queueDrainCoordinator }

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
        candidateDossierStore: CandidateDossierStore,
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
            candidateDossierStore: candidateDossierStore,
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

    // MARK: - UI Tool Interruption

    /// Whether any UI tool is currently blocked awaiting user input
    var hasPendingUITools: Bool {
        uiToolContinuationManager.hasPendingTools
    }

    /// Names of tools currently blocked awaiting user input
    var pendingUIToolNames: [String] {
        uiToolContinuationManager.pendingToolNames
    }

    /// Interrupt all pending UI tools, dismissing their UIs and returning cancelled results.
    /// Called when user presses interrupt button or escape key.
    func interruptPendingUITools() {
        guard hasPendingUITools else {
            Logger.info("🛑 Interrupt requested but no pending UI tools", category: .ai)
            return
        }

        // Clear any visible UI prompts
        toolRouter.clearChoicePrompt()
        toolRouter.clearValidationPrompt()
        toolRouter.clearPendingUploadRequests()
        toolRouter.clearSectionToggle()

        // Emit events to update UI state
        // Note: uploadRequestCancelled requires an ID but handler ignores it for clearing state
        Task {
            await eventBus.publish(.toolpane(.choicePromptCleared))
            await eventBus.publish(.toolpane(.validationPromptCleared))
            for request in pendingUploadRequests {
                await eventBus.publish(.toolpane(.uploadRequestCancelled(id: request.id)))
            }
            await eventBus.publish(.toolpane(.sectionToggleCleared))
            await eventBus.publish(.toolpane(.applicantProfileIntakeCleared))
        }

        // Resume all continuations with cancelled result
        uiToolContinuationManager.interruptAll()
        Logger.info("🛑 Pending UI tools interrupted by user", category: .ai)
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
        await eventBus.publish(.objective(.statusUpdateRequested(
            id: OnboardingObjectiveId.dossierComplete.rawValue,
            status: "completed",
            source: "user_action",
            notes: "User clicked 'End Interview' button",
            details: nil
        )))

        // Send a system-generated message to trigger ExperienceDefaults generation and finalization
        var userMessage = SwiftyJSON.JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = """
            I'm ready to finish the interview. Please:
            1. Finalize and persist the candidate dossier
            2. Complete any remaining Phase 3 objectives
            3. Call next_phase to complete the interview
            """
        await eventBus.publish(.llm(.enqueueUserMessage(payload: userMessage, isSystemGenerated: true)))
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

        // Clear document collection mode if active
        if ui.isDocumentCollectionActive {
            ui.isDocumentCollectionActive = false
            await eventBus.publish(.state(.documentCollectionActiveChanged(false)))
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
            await eventBus.publish(.objective(.statusUpdateRequested(
                id: OnboardingObjectiveId.writingSamplesCollected.rawValue,
                status: "completed",
                source: "user_action",
                notes: "User clicked 'Done with Writing Samples' button in Phase 1",
                details: nil
            )))

            // Send a system-tagged message (not chatbox) to indicate app state change
            // Using <system> tags tells Claude this is an app notification, not user speech
            var userMessage = SwiftyJSON.JSON()
            userMessage["role"].string = "user"
            userMessage["content"].string = """
                <system>User clicked 'Done with Writing Samples'. \
                The upload UI has been dismissed. Continue with the interview.</system>
                """
            await eventBus.publish(.llm(.enqueueUserMessage(payload: userMessage, isSystemGenerated: true)))
        } else {
            // Phase 3: Mark the Phase 3 writing samples objective as completed
            await eventBus.publish(.objective(.statusUpdateRequested(
                id: OnboardingObjectiveId.oneWritingSample.rawValue,
                status: "completed",
                source: "user_action",
                notes: "User clicked 'Done with Writing Samples' button in Phase 3",
                details: nil
            )))

            // Send a system-tagged message to trigger dossier compilation
            var userMessage = SwiftyJSON.JSON()
            userMessage["role"].string = "user"
            userMessage["content"].string = """
                <system>User clicked 'Done with Writing Samples'. \
                The upload UI has been dismissed. Proceed to compile the candidate dossier.</system>
                """
            await eventBus.publish(.llm(.enqueueUserMessage(payload: userMessage, isSystemGenerated: true)))
        }
    }

    /// Called when user clicks "Skip" button in Phase 1 writing sample collection
    /// Marks the writing samples objective complete (even with no samples) and continues flow
    func skipWritingSamplesCollection() async {
        Logger.info("📝 User skipped writing samples collection", category: .ai)

        // Ensure this user action always succeeds - clear blocks and auto-complete pending tools
        await ensureUserActionSucceeds(actionDescription: "Skip Writing Samples")

        // Mark the writing samples objective as completed (skipped is still complete)
        await eventBus.publish(.objective(.statusUpdateRequested(
            id: OnboardingObjectiveId.writingSamplesCollected.rawValue,
            status: "completed",
            source: "user_action",
            notes: "User chose to skip writing samples",
            details: nil
        )))

        // Send a system-generated user message to inform the LLM
        var userMessage = SwiftyJSON.JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = """
            I don't have writing samples available right now. \
            Please continue with the interview - we can develop my voice through conversation.
            """
        await eventBus.publish(.llm(.enqueueUserMessage(payload: userMessage, isSystemGenerated: true)))
    }

    /// Notify the LLM that title sets have been curated, providing the approved options.
    func notifyTitleSetsCurated(approvedSets: [TitleSet]) async {
        let setsDescription = approvedSets.enumerated().map { index, set in
            "  \(index + 1). [\"\(set.titles.joined(separator: "\", \""))\"] - \(set.emphasis.rawValue)"
        }.joined(separator: "\n")

        var payload = SwiftyJSON.JSON()
        payload["text"].string = """
            <system>
            Title Sets Curated: User has approved \(approvedSets.count) identity title sets:

            \(setsDescription)

            Choose the ONE title set that would work best for the WIDEST range of job applications. \
            Consider versatility, professional appeal, and breadth of applicability.

            Call generate_experience_defaults with your chosen titles in the `selected_titles` parameter \
            as an array of 4 strings, e.g. ["Engineer", "Developer", "Builder", "Maker"].
            </system>
            """

        await eventBus.publish(.llm(.enqueueUserMessage(payload: payload, isSystemGenerated: true)))
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
        await eventBus.publish(.objective(.statusUpdateRequested(
            id: objectiveId,
            status: status.lowercased(),
            source: "tool",
            notes: notes,
            details: details
        )))
        var result = JSON()
        result["status"].string = "completed"
        result["success"].boolValue = true
        result["objectiveId"].stringValue = objectiveId
        result["newStatus"].stringValue = status.lowercased()
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
        await eventBus.publish(.timeline(.cardDeleted(id: id, fromUI: true)))
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
        await eventBus.publish(.artifact(.metadataUpdateRequested(artifactId: artifactId, updates: updates)))
    }

    /// Cancel an upload request.
    func cancelUploadRequest(id: UUID) async {
        await eventBus.publish(.toolpane(.uploadRequestCancelled(id: id)))
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
        await container.eventBus.publish(.llm(.executeCoordinatorMessage(payload: payload)))
    }

    // MARK: - Tool Management

    func presentUploadRequest(_ request: OnboardingUploadRequest) {
        Task {
            await eventBus.publish(.toolpane(.uploadRequestPresented(request: request)))
        }
    }

    func completeUpload(id: UUID, fileURLs: [URL]) async -> JSON? {
        let result = await toolRouter.completeUpload(id: id, fileURLs: fileURLs)
        Task {
            await eventBus.publish(.toolpane(.uploadRequestCancelled(id: id)))
        }
        return result
    }

    func skipUpload(id: UUID) async -> JSON? {
        let result = await toolRouter.skipUpload(id: id)
        Task {
            await eventBus.publish(.toolpane(.uploadRequestCancelled(id: id)))
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
            await eventBus.publish(.artifact(.knowledgeCardPersisted(card: data)))
        }

        let result = toolRouter.submitValidationResponse(
            status: status,
            updatedData: updatedData,
            changes: changes,
            notes: notes
        )

        if result != nil {
            Task {
                await eventBus.publish(.toolpane(.validationPromptCleared))
            }
            // Mark skeleton_timeline objective as complete when user confirms validation
            if let validation = pendingValidation,
               validation.dataType == "skeleton_timeline",
               ["confirmed", "confirmed_with_changes", "approved", "modified"].contains(status.lowercased()) {
                await eventBus.publish(.objective(.statusUpdateRequested(
                    id: OnboardingObjectiveId.skeletonTimelineComplete.rawValue,
                    status: "completed",
                    source: "ui_timeline_validated",
                    notes: "Timeline validated by user",
                    details: nil
                )))
                Logger.debug("✅ skeleton_timeline_complete objective marked complete after validation", category: .ai)

                // Prompt for configure_enabled_sections as next step
                // next_phase will be ungated when enabledSections objective completes
                var payload = JSON()
                payload["text"].string = """
                    Timeline approved. Now configure which resume sections to include. \
                    Call configure_enabled_sections with recommendations based on user's background.
                    """
                await eventBus.publish(.llm(.sendCoordinatorMessage(payload: payload)))
                Logger.info("📋 Prompting configure_enabled_sections after timeline validation", category: .ai)
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
    /// Advance to the next phase from UI button click
    /// The action is queued and processed at a safe boundary to prevent race conditions
    func advanceToNextPhaseFromUI() async {
        let currentPhase = ui.phase

        // Determine next phase
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

        Logger.info("🚀 Phase advance queued from UI: \(currentPhase.rawValue) → \(nextPhase.rawValue)", category: .ai)

        // Queue the phase advance action for safe boundary processing
        userActionQueue.enqueue(.phaseAdvance(from: currentPhase, to: nextPhase), priority: .high)

        // Attempt to drain the queue (will check gate before processing)
        await queueDrainCoordinator.checkAndDrain()
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
        // Clear stopped flag - user took purposeful action
        if ui.isStopped {
            ui.isStopped = false
            Logger.info("🔓 Stop state cleared by user action", category: .ai)
        }
        await uiResponseCoordinator.sendChatMessage(text)
    }

    /// Interrupt current LLM operation and send the message immediately.
    /// Called when user clicks the Interrupt button.
    func interruptWithMessage(_ text: String) async {
        Logger.info("⚡ Interrupt with message requested", category: .ai)

        // 1. Cancel current LLM operation
        await requestCancelLLM()

        // 2. Clear all drain gate blocks to allow immediate processing
        drainGate.clearAllBlocks()

        // 3. Send the message (it will be queued and processed immediately since gate is clear)
        await sendChatMessage(text)
    }

    /// Stop all processing, clear queue, and silence incoming until next user action.
    /// Cleans up orphan tool calls and cancels active agents.
    func stopProcessing() async {
        Logger.info("🛑 Stop processing requested", category: .ai)

        // 1. Set stopped flag - silences all incoming processing
        ui.isStopped = true

        // 2. Cancel current LLM operation
        await requestCancelLLM()

        // 3. Kill all active agents
        await agentActivityTracker.killAllAgents()

        // 4. Clear the message queue
        await queueDrainCoordinator.reset()

        // 5. Clear queued message IDs from UI state
        ui.queuedMessageIds.removeAll()
        ui.queuedMessageCount = 0

        // 6. Clean up orphan tool calls from conversation history
        await state.getConversationLog().cleanupOrphanedToolCalls()

        // 7. Clear all drain gate blocks
        drainGate.clearAllBlocks()

        // 8. Clear processing state
        ui.isProcessing = false
        ui.isStreaming = false

        Logger.info("🛑 Stop processing complete - silenced until next user action", category: .ai)
    }

    func sendCoordinatorMessage(title: String, details: [String: String] = [:]) async {
        var payload = JSON()
        payload["title"].string = title
        var detailsJSON = JSON()
        for (key, value) in details {
            detailsJSON[key].string = value
        }
        payload["details"] = detailsJSON
        await eventBus.publish(.llm(.sendCoordinatorMessage(payload: payload)))
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
        await eventBus.publish(.processing(.stateChanged(isProcessing: false, statusMessage: nil)))

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
        await eventBus.publish(.processing(.pendingExtractionUpdated(nil, statusMessage: nil)))
        await eventBus.publish(.processing(.stateChanged(isProcessing: false, statusMessage: nil)))
        // Force batch completion so pending artifacts are sent
        await eventBus.publish(.processing(.batchUploadCompleted))

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

        await eventBus.publish(.artifact(.doneWithUploadsClicked))
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

    /// Manually trigger voice profile extraction from writing samples
    func regenerateVoiceProfile() async {
        await container.voiceProfileExtractionHandler.triggerExtraction()
    }

    /// Run LLM-powered skill deduplication manually
    func deduplicateSkills() async {
        guard let facade = llmFacade else {
            Logger.warning("Cannot deduplicate skills: LLM facade not available", category: .ai)
            return
        }
        let service = SkillsProcessingService(
            skillStore: skillStore,
            facade: facade,
            agentActivityTracker: agentActivityTracker
        )
        do {
            let result = try await service.consolidateDuplicates()
            Logger.info("✅ Skills deduplication complete: \(result.details)", category: .ai)
        } catch {
            Logger.error("❌ Skills deduplication failed: \(error.localizedDescription)", category: .ai)
        }
    }

    /// Run LLM-powered ATS synonym expansion manually
    func expandATSSkills() async {
        guard let facade = llmFacade else {
            Logger.warning("Cannot expand ATS skills: LLM facade not available", category: .ai)
            return
        }
        let service = SkillsProcessingService(
            skillStore: skillStore,
            facade: facade,
            agentActivityTracker: agentActivityTracker
        )
        do {
            let result = try await service.expandATSSynonyms()
            Logger.info("✅ ATS expansion complete: \(result.details)", category: .ai)
        } catch {
            Logger.error("❌ ATS expansion failed: \(error.localizedDescription)", category: .ai)
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
