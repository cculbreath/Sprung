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

    /// Returns the card merge service for merging document inventories
    var cardMergeService: CardMergeService {
        container.cardMergeService
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
        resRefStore: ResRefStore,
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
        // Configure lifecycle controller with state update subscriber
        container.lifecycleController.setStateUpdateSubscriber { [weak self] in
            self?.subscribeToStateUpdates()
        }
        Logger.info("🎯 OnboardingInterviewCoordinator initialized with event-driven architecture", category: .ai)
        Task { await subscribeToEvents() }
        Task { await profilePersistenceHandler.start() }
    }
    // MARK: - Service Updates
    func updateLLMFacade(_ facade: LLMFacade?) {
        container.updateLLMFacade(facade)
        // Re-register tools with new agent if available
        container.reregisterTools { [weak self] message in
            self?.ui.modelAvailabilityMessage = message
        }
        Logger.info("🔄 LLMFacade updated in Coordinator", category: .ai)
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
        // Load archived artifacts before starting
        await loadArchivedArtifacts()
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
            Logger.info("🗑️ UI deletion synced: removed card \(id) from coordinator cache", category: .ai)
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

    /// Fetch URL content and create artifact via agent web search
    func fetchURLForArtifact(_ urlString: String) async {
        Logger.info("🌐 Requesting URL fetch for artifact: \(urlString)", category: .ai)
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
                    id: "skeleton_timeline",
                    status: "completed",
                    source: "ui_timeline_validated",
                    notes: "Timeline validated by user",
                    details: nil
                ))
                // UNGATE: Allow next_phase now that timeline is approved
                await container.sessionUIState.includeTool(OnboardingToolName.nextPhase.rawValue)
                Logger.info("🔓 Ungated next_phase after timeline approval", category: .ai)
                Logger.info("✅ skeleton_timeline objective marked complete after validation", category: .ai)
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
    /// Uses metadataJSON as base to preserve all fields (card_inventory, summary, etc.)
    private func artifactRecordToJSON(_ record: OnboardingArtifactRecord) -> JSON {
        // Start with the full persisted record (includes card_inventory, metadata, etc.)
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
        json["filename"].string = record.sourceFilename
        json["extracted_text"].string = record.extractedContent
        json["source_hash"].string = record.sourceHash
        json["raw_file_path"].string = record.rawFileRelativePath
        json["plan_item_id"].string = record.planItemId
        json["ingested_at"].string = ISO8601DateFormatter().string(from: record.ingestedAt)
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

        // Deactivate document collection UI and clear waiting state
        await MainActor.run {
            ui.isDocumentCollectionActive = false
        }
        await container.sessionUIState.setDocumentCollectionActive(false)

        // Send message to LLM
        await sendChatMessage("I'm done uploading documents. (Note: Some document extractions were cancelled.) Please assess the completeness of my evidence.")

        Logger.info("✅ Extraction agents cancelled and document upload phase finished", category: .ai)
    }

    /// Activate document collection UI and gate all tools until user clicks "Done with Uploads"
    func activateDocumentCollection() async {
        await MainActor.run {
            ui.isDocumentCollectionActive = true
        }
        await container.sessionUIState.setDocumentCollectionActive(true)
        Logger.info("📂 Document collection activated - tools gated until 'Done with Uploads'", category: .ai)
    }

    /// Finish uploads and trigger card merge directly (bypassing LLM tool call).
    /// Called when user clicks "Done with Uploads" button.
    func finishUploadsAndMergeCards() async {
        Logger.info("📋 User finished uploads - triggering card merge directly", category: .ai)

        // Deactivate document collection UI and clear waiting state (re-enable tools)
        await MainActor.run {
            ui.isDocumentCollectionActive = false
        }
        await container.sessionUIState.setDocumentCollectionActive(false)

        // Track merge in Agents pane
        let agentId = await MainActor.run {
            agentActivityTracker.trackAgent(
                type: .cardMerge,
                name: "Merging Card Inventories",
                task: nil as Task<Void, Never>?
            )
        }

        await MainActor.run {
            agentActivityTracker.appendTranscript(
                agentId: agentId,
                entryType: .system,
                content: "Starting card inventory merge"
            )
        }

        // Get timeline for context
        let timeline = await state.artifacts.skeletonTimeline

        // Run the merge
        let mergedInventory: MergedCardInventory
        do {
            mergedInventory = try await cardMergeService.mergeInventories(timeline: timeline)
        } catch CardMergeService.CardMergeError.noInventories {
            await MainActor.run {
                agentActivityTracker.markFailed(agentId: agentId, error: "No document inventories available")
            }
            Logger.warning("⚠️ No document inventories available for merge", category: .ai)
            await sendChatMessage("I'm done uploading documents, but no card inventories were found. Please check the documents.")
            return
        } catch {
            await MainActor.run {
                agentActivityTracker.markFailed(agentId: agentId, error: error.localizedDescription)
            }
            Logger.error("❌ Card merge failed: \(error.localizedDescription)", category: .ai)
            await sendChatMessage("I'm done uploading documents. Card merge failed: \(error.localizedDescription)")
            return
        }

        // Update transcript with results
        let stats = mergedInventory.stats
        let typeBreakdown = "employment: \(stats.cardsByType.employment), project: \(stats.cardsByType.project), skill: \(stats.cardsByType.skill), achievement: \(stats.cardsByType.achievement), education: \(stats.cardsByType.education)"
        await MainActor.run {
            agentActivityTracker.appendTranscript(
                agentId: agentId,
                entryType: .toolResult,
                content: "Merged \(mergedInventory.mergedCards.count) cards from \(stats.totalInputCards) input cards",
                details: "Types: \(typeBreakdown)"
            )
        }

        // Build plan items from merged inventory
        let planItems = mergedInventory.mergedCards.map { mergedCard in
            var artifactIds = [mergedCard.primarySource.documentId]
            artifactIds.append(contentsOf: mergedCard.supportingSources.map { $0.documentId })

            return KnowledgeCardPlanItem(
                id: mergedCard.cardId,
                title: mergedCard.title,
                type: planItemType(from: mergedCard.cardType),
                description: mergedCard.dateRange,
                status: .pending,
                timelineEntryId: nil,
                assignedArtifactIds: artifactIds
            )
        }

        // Update UI with plan items
        await updateKnowledgeCardPlan(
            items: planItems,
            currentFocus: nil,
            message: "Review card assignments below"
        )

        // Store proposals for dispatch_kc_agents
        var proposals = JSON([])
        for mergedCard in mergedInventory.mergedCards {
            var proposal = JSON()
            proposal["card_id"].string = mergedCard.cardId
            proposal["card_type"].string = mergedCard.cardType
            proposal["title"].string = mergedCard.title
            proposals.arrayObject?.append(proposal.dictionaryObject ?? [:])
        }
        await state.storeCardProposals(proposals)

        // Gate dispatch_kc_agents until user approves
        await state.excludeTool(OnboardingToolName.dispatchKCAgents.rawValue)

        // Store merged inventory for detail views and gaps
        await MainActor.run {
            ui.mergedInventory = mergedInventory
        }

        // Persist merged inventory to SwiftData (expensive LLM call result)
        if let inventoryJSON = try? JSONEncoder().encode(mergedInventory),
           let jsonString = String(data: inventoryJSON, encoding: .utf8) {
            await eventBus.publish(.mergedInventoryStored(inventoryJSON: jsonString))
        }

        // Emit event for UI
        await eventBus.publish(.cardAssignmentsProposed(
            assignmentCount: mergedInventory.mergedCards.count,
            gapCount: mergedInventory.gaps.count
        ))

        // Mark agent as completed
        await MainActor.run {
            agentActivityTracker.markCompleted(agentId: agentId)
        }

        Logger.info("✅ Merged \(mergedInventory.mergedCards.count) cards from documents", category: .ai)

        // Build summary for LLM
        let cardsByType = Dictionary(grouping: mergedInventory.mergedCards, by: { $0.cardType })
        let typeSummary = cardsByType.map { "\($0.value.count) \($0.key)" }.joined(separator: ", ")

        // Build gap summary for LLM
        var gapSummary = ""
        if !mergedInventory.gaps.isEmpty {
            let gapDescriptions = mergedInventory.gaps.prefix(5).map { gap -> String in
                let gapTypeDescription: String
                switch gap.gapType {
                case .missingPrimarySource: gapTypeDescription = "needs primary documentation"
                case .insufficientDetail: gapTypeDescription = "needs more detail"
                case .noQuantifiedOutcomes: gapTypeDescription = "needs quantified outcomes"
                }
                return "• \(gap.cardTitle): \(gapTypeDescription)"
            }
            gapSummary = "\n\nDocumentation gaps identified (\(mergedInventory.gaps.count) total):\n" + gapDescriptions.joined(separator: "\n")
            if mergedInventory.gaps.count > 5 {
                gapSummary += "\n...and \(mergedInventory.gaps.count - 5) more"
            }
        }

        // Notify LLM of results with gaps
        await sendChatMessage("""
            I'm done uploading documents. The system has merged card inventories and found \(mergedInventory.mergedCards.count) potential knowledge cards (\(typeSummary)). \
            Please review the proposed cards with me. I can exclude any cards that aren't relevant to me.\(gapSummary)
            """)
    }

    /// Convert card type string to plan item type
    private func planItemType(from cardType: String) -> KnowledgeCardPlanItem.ItemType {
        switch cardType {
        case "employment": return .job
        case "job": return .job
        case "skill": return .skill
        case "project": return .project
        case "achievement": return .achievement
        case "education": return .education
        default: return .job
        }
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
