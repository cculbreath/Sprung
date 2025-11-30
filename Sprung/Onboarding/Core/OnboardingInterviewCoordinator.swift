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
    // MARK: - Private Accessors (for internal use)
    // Session & Lifecycle
    private var sessionCoordinator: InterviewSessionCoordinator { container.sessionCoordinator }
    private var lifecycleController: InterviewLifecycleController { container.lifecycleController }
    // Query Coordinators
    private var artifactQueryCoordinator: ArtifactQueryCoordinator { container.artifactQueryCoordinator }
    // UI State
    private var uiStateUpdateHandler: UIStateUpdateHandler { container.uiStateUpdateHandler }
    private var uiResponseCoordinator: UIResponseCoordinator { container.uiResponseCoordinator }
    private var coordinatorEventRouter: CoordinatorEventRouter { container.coordinatorEventRouter! }
    // Phase & Objective Management
    private var phaseTransitionController: PhaseTransitionController { container.phaseTransitionController }
    // Services
    private var extractionManagementService: ExtractionManagementService { container.extractionManagementService }
    private var timelineManagementService: TimelineManagementService { container.timelineManagementService }
    private var ingestionCoordinator: IngestionCoordinator { container.ingestionCoordinator }
    private var profilePersistenceHandler: ProfilePersistenceHandler { container.profilePersistenceHandler }
    // Tool Interaction
    private var toolInteractionCoordinator: ToolInteractionCoordinator { container.toolInteractionCoordinator! }
    // Debug/Reset only
    #if DEBUG
    private var applicantProfileStore: ApplicantProfileStore { container.getApplicantProfileStore() }
    #endif
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
    var pendingPhaseAdvanceRequest: OnboardingPhaseAdvanceRequest? {
        get async {
            await state.pendingPhaseAdvanceRequest
        }
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
        dataStore: InterviewDataStore,
        preferences: OnboardingPreferences
    ) {
        // Create dependency container with all service wiring
        self.container = OnboardingDependencyContainer(
            openAIService: openAIService,
            llmFacade: llmFacade,
            documentExtractionService: documentExtractionService,
            applicantProfileStore: applicantProfileStore,
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
        Task { await ingestionCoordinator.start() }
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
        await sessionCoordinator.startInterview(resumeExisting: resumeExisting)
    }
    func endInterview() async {
        await sessionCoordinator.endInterview()
    }
    // MARK: - Evidence Handling
    func handleEvidenceUpload(url: URL, requirementId: String) async {
        await ingestionCoordinator.handleEvidenceUpload(url: url, requirementId: requirementId)
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
        await eventBus.publish(.timelineCardDeleted(id: id))
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
    func approvePhaseAdvance() async {
        guard let request = await state.pendingPhaseAdvanceRequest else { return }
        await eventBus.publish(.phaseAdvanceApproved(request: request))
    }
    func denyPhaseAdvance(feedback: String?) async {
        await eventBus.publish(.phaseAdvanceDenied(feedback: feedback))
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
    func uploadFilesDirectly(_ fileURLs: [URL]) async {
        await uiResponseCoordinator.uploadFilesDirectly(fileURLs)
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
    func requestCancelLLM() async {
        await uiResponseCoordinator.requestCancelLLM()
    }
    // MARK: - Data Store Management (Delegated to InterviewSessionCoordinator)
    func loadPersistedArtifacts() async {
        await sessionCoordinator.loadPersistedArtifacts()
    }
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
        await MainActor.run {
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
