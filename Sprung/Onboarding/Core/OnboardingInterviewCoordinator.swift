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
    // MARK: - Private Accessors (for internal use)
    // Session & Lifecycle
    private var sessionCoordinator: InterviewSessionCoordinator { container.sessionCoordinator }
    private var lifecycleController: InterviewLifecycleController { container.lifecycleController }
    // Query Coordinators
    private var artifactQueryCoordinator: ArtifactQueryCoordinator { container.artifactQueryCoordinator }
    // UI State
    private var uiStateUpdateHandler: UIStateUpdateHandler { container.uiStateUpdateHandler }
    private var uiResponseCoordinator: UIResponseCoordinator { container.uiResponseCoordinator }
    private var coordinatorEventRouter: CoordinatorEventRouter { container.coordinatorEventRouter }
    // Phase & Objective Management
    private var phaseTransitionController: PhaseTransitionController { container.phaseTransitionController }
    // Services
    private var extractionManagementService: ExtractionManagementService { container.extractionManagementService }
    private var timelineManagementService: TimelineManagementService { container.timelineManagementService }
    private var profilePersistenceHandler: ProfilePersistenceHandler { container.profilePersistenceHandler }
    // Tool Interaction
    private var toolInteractionCoordinator: ToolInteractionCoordinator { container.toolInteractionCoordinator }
    // Data Stores (used for data existence checks and reset)
    private var applicantProfileStore: ApplicantProfileStore { container.getApplicantProfileStore() }
    private var resRefStore: ResRefStore { container.getResRefStore() }
    private var coverRefStore: CoverRefStore { container.getCoverRefStore() }
    private var experienceDefaultsStore: ExperienceDefaultsStore { container.getExperienceDefaultsStore() }
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

    /// Knowledge cards created during onboarding (persisted as ResRefs)
    var onboardingKnowledgeCards: [ResRef] {
        container.onboardingKnowledgeCards
    }

    /// All knowledge cards (ResRefs) including both onboarding and manually created
    var allKnowledgeCards: [ResRef] {
        resRefStore.resRefs
    }

    /// Access to ResRefStore for CRUD operations on knowledge cards
    func getResRefStore() -> ResRefStore {
        resRefStore
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

    /// Returns the KC agent service for parallel knowledge card generation
    func getKCAgentService() -> KnowledgeCardAgentService {
        container.getKCAgentService()
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
    func eventStream(for topic: EventTopic) async -> AsyncStream<OnboardingEvent> {
        await eventBus.stream(topic: topic)
    }
    // MARK: - Initialization
    init(
        openAIService: OpenAIService?,
        llmFacade: LLMFacade?,
        documentExtractionService: DocumentExtractionService,
        applicantProfileStore: ApplicantProfileStore,
        resRefStore: ResRefStore,
        coverRefStore: CoverRefStore,
        experienceDefaultsStore: ExperienceDefaultsStore,
        sessionStore: OnboardingSessionStore,
        dataStore: InterviewDataStore,
        preferences: OnboardingPreferences
    ) {
        // Create dependency container with all service wiring
        self.container = OnboardingDependencyContainer(
            openAIService: openAIService,
            llmFacade: llmFacade,
            documentExtractionService: documentExtractionService,
            applicantProfileStore: applicantProfileStore,
            resRefStore: resRefStore,
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
        // Configure session coordinator with state update subscriber
        container.sessionCoordinator.setStateUpdateSubscriber { [weak self] in
            self?.subscribeToStateUpdates()
        }
        Logger.info("🎯 OnboardingInterviewCoordinator initialized with event-driven architecture", category: .ai)
        Task { await subscribeToEvents() }
        Task { await profilePersistenceHandler.start() }
    }
    // MARK: - Service Updates
    func updateOpenAIService(_ service: OpenAIService?) {
        container.updateOpenAIService(service)
        // Re-register tools with new agent if available
        container.reregisterTools { [weak self] message in
            self?.ui.modelAvailabilityMessage = message
        }
        Logger.info("🔄 OpenAIService updated in Coordinator", category: .ai)
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
    // MARK: - Interview Lifecycle (Delegated to InterviewSessionCoordinator)
    func startInterview(resumeExisting: Bool = false) async -> Bool {
        // Load archived artifacts before starting
        await loadArchivedArtifacts()
        return await sessionCoordinator.startInterview(resumeExisting: resumeExisting)
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
        // Check for onboarding ResRefs (knowledge cards)
        let onboardingResRefs = resRefStore.resRefs.filter { $0.isFromOnboarding }
        if !onboardingResRefs.isEmpty {
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
            container.sessionStore.deleteSession(session)
            Logger.info("🗑️ Deleted SwiftData session: \(session.id)", category: .ai)
        }
    }

    /// Clear all onboarding data: session, ResRefs, CoverRefs, ExperienceDefaults, and ApplicantProfile
    /// Used when user chooses "Start Over" to begin fresh
    func clearAllOnboardingData() {
        Logger.info("🗑️ Clearing all onboarding data", category: .ai)
        // Delete session
        deleteCurrentSession()
        // Delete onboarding ResRefs (knowledge cards)
        resRefStore.deleteOnboardingResRefs()
        // Delete all CoverRefs
        for coverRef in coverRefStore.storedCoverRefs {
            coverRefStore.deleteCoverRef(coverRef)
        }
        Logger.info("🗑️ Deleted all CoverRefs", category: .ai)
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
        Logger.info("🗑️ Cleared ExperienceDefaults", category: .ai)
        // Reset ApplicantProfile to defaults (including photo)
        applicantProfileStore.reset()
        Logger.info("🗑️ Reset ApplicantProfile", category: .ai)
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

    /// Called when user clicks "Done with Writing Samples" button in Phase 3
    /// Marks the writing samples objective complete and triggers dossier compilation
    func completeWritingSamplesCollection() async {
        Logger.info("📝 User marked writing samples collection as complete", category: .ai)

        // Mark the writing samples objective as completed
        await eventBus.publish(.objectiveStatusUpdateRequested(
            id: OnboardingObjectiveId.oneWritingSample.rawValue,
            status: "completed",
            source: "user_action",
            notes: "User clicked 'Done with Writing Samples' button",
            details: nil
        ))

        // Send a system-generated user message to trigger dossier compilation
        var userMessage = SwiftyJSON.JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = """
            I'm done uploading writing samples. \
            Please proceed to compile my candidate dossier.
            """
        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
    }

    // MARK: - Evidence Handling
    func handleEvidenceUpload(url: URL, requirementId: String) async {
        await container.artifactIngestionCoordinator.handleEvidenceUpload(url: url, requirementId: requirementId)
    }
    // MARK: - Phase Management
    func advancePhase() async -> InterviewPhase? {
        let newPhase = await phaseTransitionController.advancePhase()
        let completedSteps = await state.completedWizardSteps
        let currentStep = await state.currentWizardStep
        synchronizeWizardTracker(currentStep: currentStep, completedSteps: completedSteps)
        return newPhase
    }
    func getCompletedObjectiveIds() async -> Set<String> {
        await phaseTransitionController.getCompletedObjectiveIds()
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
    // MARK: - Timeline Management (Delegated to TimelineManagementService)
    func applyUserTimelineUpdate(cards: [TimelineCard], meta: JSON?, diff: TimelineDiff) async {
        await uiResponseCoordinator.applyUserTimelineUpdate(cards: cards, meta: meta, diff: diff)
    }
    func createTimelineCard(fields: JSON) async -> JSON {
        await timelineManagementService.createTimelineCard(fields: fields)
    }
    func updateTimelineCard(id: String, fields: JSON) async -> JSON {
        await timelineManagementService.updateTimelineCard(id: id, fields: fields)
    }
    func deleteTimelineCard(id: String) async -> JSON {
        await timelineManagementService.deleteTimelineCard(id: id)
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
            Logger.info("🗑️ UI deletion synced: removed card \(id) from coordinator cache", category: .ai)
        }
        // Also emit the event so StateCoordinator updates its state
        // Pass fromUI: true so CoordinatorEventRouter doesn't re-increment the UI token
        await eventBus.publish(.timelineCardDeleted(id: id, fromUI: true))
    }
    func reorderTimelineCards(orderedIds: [String]) async -> JSON {
        await timelineManagementService.reorderTimelineCards(orderedIds: orderedIds)
    }
    func requestPhaseTransition(from: String, to: String, reason: String?) async {
        await timelineManagementService.requestPhaseTransition(from: from, to: to, reason: reason)
    }
    func missingObjectives() async -> [String] {
        await timelineManagementService.missingObjectives()
    }
    // MARK: - Artifact Queries (Delegated to ArtifactQueryCoordinator)
    func listArtifactSummaries() async -> [JSON] {
        await artifactQueryCoordinator.listArtifactSummaries()
    }
    func listArtifactRecords() async -> [JSON] {
        await artifactQueryCoordinator.listArtifactRecords()
    }
    func getArtifactRecord(id: String) async -> JSON? {
        await artifactQueryCoordinator.getArtifactRecord(id: id)
    }
    func requestArtifactMetadataUpdate(artifactId: String, updates: JSON) async {
        await artifactQueryCoordinator.requestMetadataUpdate(artifactId: artifactId, updates: updates)
    }
    func getArtifact(id: String) async -> JSON? {
        await artifactQueryCoordinator.getArtifact(id: id)
    }
    func cancelUploadRequest(id: UUID) async {
        await artifactQueryCoordinator.cancelUploadRequest(id: id)
    }
    func nextPhase() async -> InterviewPhase? {
        await phaseTransitionController.nextPhase()
    }
    // MARK: - Extraction Management (Delegated to ExtractionManagementService)
    func setExtractionStatus(_ extraction: OnboardingPendingExtraction?) {
        extractionManagementService.setExtractionStatus(extraction)
    }
    func updateExtractionProgress(with update: ExtractionProgressUpdate) {
        extractionManagementService.updateExtractionProgress(with: update)
    }
    func setStreamingStatus(_ status: String?) async {
        await extractionManagementService.setStreamingStatus(status)
    }
    private func synchronizeWizardTracker(
        currentStep: StateCoordinator.WizardStep,
        completedSteps: Set<StateCoordinator.WizardStep>
    ) {
        extractionManagementService.synchronizeWizardTracker(
            currentStep: currentStep,
            completedSteps: completedSteps
        )
    }
    // MARK: - Knowledge Card Plan
    func updateKnowledgeCardPlan(
        items: [KnowledgeCardPlanItem],
        currentFocus: String?,
        message: String?
    ) async {
        ui.knowledgeCardPlan = items
        ui.knowledgeCardPlanFocus = currentFocus
        ui.knowledgeCardPlanMessage = message
        // Emit event for persistence
        await eventBus.publish(.knowledgeCardPlanUpdated(items: items, currentFocus: currentFocus, message: message))
        Logger.info("📋 Knowledge card plan updated: \(items.count) items, focus=\(currentFocus ?? "none"), phase=\(ui.phase.rawValue)", category: .ai)
    }

    /// Get the currently focused plan item ID
    func getCurrentPlanItemFocus() -> String? {
        ui.knowledgeCardPlanFocus
    }

    /// Check if there's a pending knowledge card awaiting validation
    func hasPendingKnowledgeCard() -> Bool {
        coordinatorEventRouter.hasPendingKnowledgeCard()
    }

    // MARK: - Artifact Ingestion (Git Repos, Documents)
    // Uses ArtifactIngestionCoordinator for unified ingestion pipeline

    /// Start git repository analysis using the async ingestion pipeline
    func startGitRepoAnalysis(_ repoURL: URL) async {
        let currentPlanItemId = ui.knowledgeCardPlanFocus
        Logger.info("🔬 Starting git repo analysis via ingestion pipeline: \(repoURL.path)", category: .ai)
        await container.artifactIngestionCoordinator.ingestGitRepository(
            repoURL: repoURL,
            planItemId: currentPlanItemId
        )
    }

    /// Ingest document files using the async ingestion pipeline
    func ingestDocuments(_ fileURLs: [URL]) async {
        let currentPlanItemId = ui.knowledgeCardPlanFocus
        for url in fileURLs {
            await container.artifactIngestionCoordinator.ingestDocument(
                fileURL: url,
                planItemId: currentPlanItemId
            )
        }
    }

    /// Check if there are pending artifacts for the current knowledge card item
    func hasPendingArtifactsForCurrentItem() async -> Bool {
        guard let planItemId = ui.knowledgeCardPlanFocus else { return false }
        return await container.artifactIngestionCoordinator.hasPendingArtifacts(forPlanItem: planItemId)
    }

    /// Get status message for pending artifacts
    func getPendingArtifactStatus() async -> String? {
        guard let planItemId = ui.knowledgeCardPlanFocus else { return nil }
        return await container.artifactIngestionCoordinator.getPendingStatusMessage(forPlanItem: planItemId)
    }

    // MARK: - Tool Management (Delegated to ToolInteractionCoordinator)
    func presentUploadRequest(_ request: OnboardingUploadRequest) {
        toolInteractionCoordinator.presentUploadRequest(request)
    }
    func completeUpload(id: UUID, fileURLs: [URL]) async -> JSON? {
        await toolInteractionCoordinator.completeUpload(id: id, fileURLs: fileURLs)
    }
    func skipUpload(id: UUID) async -> JSON? {
        await toolInteractionCoordinator.skipUpload(id: id)
    }
    func presentChoicePrompt(_ prompt: OnboardingChoicePrompt) {
        toolInteractionCoordinator.presentChoicePrompt(prompt)
    }
    func submitChoice(optionId: String) -> JSON? {
        toolInteractionCoordinator.submitChoice(optionId: optionId)
    }
    func presentValidationPrompt(_ prompt: OnboardingValidationPrompt) {
        toolInteractionCoordinator.presentValidationPrompt(prompt)
    }
    func submitValidationResponse(
        status: String,
        updatedData: JSON?,
        changes: JSON?,
        notes: String?
    ) async -> JSON? {
        await toolInteractionCoordinator.submitValidationResponse(
            status: status,
            updatedData: updatedData,
            changes: changes,
            notes: notes
        )
    }
    // MARK: - Applicant Profile Intake Facade Methods (Delegated to ToolInteractionCoordinator)
    func beginProfileUpload() {
        let request = toolInteractionCoordinator.beginProfileUpload()
        presentUploadRequest(request)
    }
    func beginProfileURLEntry() {
        toolInteractionCoordinator.beginProfileURLEntry()
    }
    func beginProfileContactsFetch() {
        toolInteractionCoordinator.beginProfileContactsFetch()
    }
    func beginProfileManualEntry() {
        toolInteractionCoordinator.beginProfileManualEntry()
    }
    func resetProfileIntakeToOptions() {
        toolInteractionCoordinator.resetProfileIntakeToOptions()
    }
    func submitProfileDraft(draft: ApplicantProfileDraft, source: OnboardingApplicantProfileIntakeState.Source) async {
        await uiResponseCoordinator.submitProfileDraft(draft: draft, source: source)
    }
    func submitProfileURL(_ urlString: String) async {
        await uiResponseCoordinator.submitProfileURL(urlString)
    }
    // MARK: - Phase Advance
    /// Request phase advance from UI button (sends user message to trigger next_phase tool)
    func requestPhaseAdvanceFromUI() async {
        var payload = JSON()
        payload["text"].string = "<chatbox>I'm ready to move on to the next phase.</chatbox>"
        await eventBus.publish(.llmSendUserMessage(payload: payload, isSystemGenerated: true))
    }
    // MARK: - UI Response Handling (Send User Messages)
    func submitChoiceSelection(_ selectionIds: [String]) async {
        await uiResponseCoordinator.submitChoiceSelection(selectionIds)
    }
    func completeUploadAndResume(id: UUID, fileURLs: [URL]) async {
        await uiResponseCoordinator.completeUploadAndResume(id: id, fileURLs: fileURLs, coordinator: self)
    }
    func completeUploadAndResume(id: UUID, link: URL) async {
        await uiResponseCoordinator.completeUploadAndResume(id: id, link: link, coordinator: self)
    }
    func skipUploadAndResume(id: UUID) async {
        await uiResponseCoordinator.skipUploadAndResume(id: id, coordinator: self)
    }

    /// Uploads files directly (from persistent drop zone, no pending request needed)
    func uploadFilesDirectly(_ fileURLs: [URL], extractionMethod: LargePDFExtractionMethod? = nil) async {
        await uiResponseCoordinator.uploadFilesDirectly(fileURLs, extractionMethod: extractionMethod)
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
    func confirmSectionToggle(enabled: [String]) async {
        await uiResponseCoordinator.confirmSectionToggle(enabled: enabled)
    }
    func rejectSectionToggle(reason: String) async {
        await uiResponseCoordinator.rejectSectionToggle(reason: reason)
    }
    func clearValidationPromptAndNotifyLLM(message: String) async {
        await uiResponseCoordinator.clearValidationPromptAndNotifyLLM(message: message)
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
        // Delete from repository (returns the deleted artifact for notification)
        guard let deleted = await state.deleteArtifactRecord(id: id) else {
            Logger.warning("⚠️ Failed to delete artifact: \(id) - not found", category: .ai)
            return
        }

        let filename = deleted["filename"].stringValue
        let title = deleted["metadata"]["title"].string ?? filename

        // Update UI state
        await MainActor.run {
            ui.artifactRecords = container.artifactRepository.artifactRecordsSync
        }

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

        Logger.info("🗑️ Artifact deleted and LLM notified: \(filename)", category: .ai)
    }

    // MARK: - Archived Artifacts Management

    /// Load archived artifacts from SwiftData into the repository cache.
    /// Called during coordinator initialization.
    func loadArchivedArtifacts() async {
        let archivedJSON = container.sessionPersistenceHandler.getArchivedArtifactsAsJSON()
        await container.artifactRepository.setArchivedArtifacts(archivedJSON)
        await MainActor.run {
            ui.archivedArtifactCount = archivedJSON.count
        }
        Logger.info("📦 Loaded \(archivedJSON.count) archived artifacts", category: .ai)
    }

    /// Get archived artifacts for UI display.
    func getArchivedArtifacts() -> [JSON] {
        container.artifactRepository.archivedArtifactsSync
    }

    /// Promote an archived artifact to the current session.
    /// This makes the artifact available to the LLM and adds it to the current interview.
    func promoteArchivedArtifact(id: String) async {
        guard let session = container.sessionPersistenceHandler.getActiveSession() else {
            Logger.warning("⚠️ Cannot promote artifact: no active session", category: .ai)
            return
        }

        guard let artifactRecord = container.sessionStore.findArtifactById(id) else {
            Logger.warning("⚠️ Cannot promote artifact: not found in SwiftData: \(id)", category: .ai)
            return
        }

        // Update SwiftData: move artifact to current session
        container.sessionStore.promoteArtifact(artifactRecord, to: session)

        // Convert to JSON for in-memory storage
        let artifactJSON = artifactRecordToJSON(artifactRecord)

        // Add to current session's in-memory artifact list
        await container.artifactRepository.addArtifactRecord(artifactJSON)

        // Remove from archived cache
        await container.artifactRepository.removeFromArchivedCache(id: id)

        // Emit event to notify LLM and other handlers
        await eventBus.publish(.artifactRecordProduced(record: artifactJSON))

        // Update UI state
        await MainActor.run {
            ui.artifactRecords = container.artifactRepository.artifactRecordsSync
            ui.archivedArtifactCount = container.artifactRepository.archivedArtifactsSync.count
        }

        let filename = artifactRecord.sourceFilename
        Logger.info("📦 Promoted archived artifact: \(filename)", category: .ai)
    }

    /// Permanently delete an archived artifact.
    /// This removes the artifact from SwiftData - it cannot be recovered.
    func deleteArchivedArtifact(id: String) async {
        guard let artifactRecord = container.sessionStore.findArtifactById(id) else {
            Logger.warning("⚠️ Cannot delete archived artifact: not found: \(id)", category: .ai)
            return
        }

        let filename = artifactRecord.sourceFilename

        // Delete from SwiftData
        container.sessionStore.deleteArtifact(artifactRecord)

        // Remove from archived cache
        await container.artifactRepository.removeFromArchivedCache(id: id)

        // Update UI state
        await MainActor.run {
            ui.archivedArtifactCount = container.artifactRepository.archivedArtifactsSync.count
        }

        Logger.info("🗑️ Permanently deleted archived artifact: \(filename)", category: .ai)
    }

    /// Demote an artifact from the current session to archived status.
    /// This removes the artifact from the current interview but keeps it available for future use.
    func demoteArtifact(id: String) async {
        guard let artifactRecord = container.sessionStore.findArtifactById(id) else {
            Logger.warning("⚠️ Cannot demote artifact: not found: \(id)", category: .ai)
            return
        }

        let filename = artifactRecord.sourceFilename

        // Remove from session (set session to nil)
        artifactRecord.session = nil
        container.sessionStore.saveContext()

        // Remove from in-memory current artifacts
        _ = await container.artifactRepository.deleteArtifactRecord(id: id)

        // Refresh archived cache
        await container.artifactRepository.refreshArchivedArtifacts(
            container.sessionPersistenceHandler.getArchivedArtifactsAsJSON()
        )

        // Update UI state
        await MainActor.run {
            ui.artifactRecords = container.artifactRepository.artifactRecordsSync
            ui.archivedArtifactCount = container.artifactRepository.archivedArtifactsSync.count
        }

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

    /// Convert OnboardingArtifactRecord to JSON format.
    private func artifactRecordToJSON(_ record: OnboardingArtifactRecord) -> JSON {
        var json = JSON()
        json["id"].string = record.id.uuidString
        json["source_type"].string = record.sourceType
        json["filename"].string = record.sourceFilename
        json["extracted_text"].string = record.extractedContent
        json["source_hash"].string = record.sourceHash
        json["raw_file_path"].string = record.rawFileRelativePath
        json["plan_item_id"].string = record.planItemId
        json["ingested_at"].string = ISO8601DateFormatter().string(from: record.ingestedAt)
        if let metadataJSON = record.metadataJSON,
           let data = metadataJSON.data(using: .utf8),
           let metadata = try? JSON(data: data) {
            json["metadata"] = metadata
            // Also extract summary/brief_description to top level for easier access
            if let summary = metadata["summary"].string {
                json["summary"].string = summary
            }
            if let brief = metadata["brief_description"].string {
                json["brief_description"].string = brief
            }
        }
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
        Logger.info("🛑 Cancelling extraction agents and finishing uploads", category: .ai)

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

        // Deactivate document collection UI
        await MainActor.run {
            ui.isDocumentCollectionActive = false
        }

        // Send message to LLM
        await sendChatMessage("I'm done uploading documents. (Note: Some document extractions were cancelled.) Please assess the completeness of my evidence.")

        Logger.info("✅ Extraction agents cancelled and document upload phase finished", category: .ai)
    }

    // MARK: - Data Store Management (Delegated to InterviewSessionCoordinator)
    func clearArtifacts() {
        sessionCoordinator.clearArtifacts()
    }
    func resetStore() async {
        await sessionCoordinator.resetStore()
    }
    // MARK: - Utility
    func notifyInvalidModel(id: String) {
        Logger.warning("⚠️ Invalid model id reported: \(id)", category: .ai)
        ui.modelAvailabilityMessage = "Your selected model (\(id)) is not available. Choose another model in Settings."
        uiResponseCoordinator.notifyInvalidModel(id: id)
    }
    func clearModelAvailabilityMessage() {
        ui.modelAvailabilityMessage = nil
    }
    func transcriptExportString() -> String {
        ChatTranscriptFormatter.format(messages: ui.messages)
    }
    func buildSystemPrompt(for phase: InterviewPhase) -> String {
        phaseTransitionController.buildSystemPrompt(for: phase)
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
    func resetAllOnboardingData() async {
        Logger.info("🗑️ Resetting all onboarding data", category: .ai)
        // Delete SwiftData session
        deleteCurrentSession()
        Logger.info("✅ SwiftData session deleted", category: .ai)
        await MainActor.run {
            // Delete onboarding knowledge cards (ResRefs with isFromOnboarding=true)
            resRefStore.deleteOnboardingResRefs()
            Logger.info("✅ Onboarding knowledge cards deleted", category: .ai)

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
