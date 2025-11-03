import Foundation
import Observation
import SwiftyJSON
import SwiftOpenAI
import UniformTypeIdentifiers

@MainActor
@Observable
final class OnboardingInterviewCoordinator {
    struct ObjectiveStatusUpdate {
        let id: String
        let status: ObjectiveStatus
        let source: String
        let details: [String: String]?
    }
    private let chatTranscriptStore: ChatTranscriptStore
    let toolRouter: OnboardingToolRouter // Central router that owns handler state surfaced to SwiftUI
    let wizardTracker: WizardProgressTracker
    let phaseRegistry: PhaseScriptRegistry
    private let interviewState: InterviewState
    let toolRegistry: ToolRegistry
    private let toolExecutor: ToolExecutor
    private let openAIService: OpenAIService?

    // MARK: - Data Store Dependencies (merged from OnboardingDataStoreManager)

    private let applicantProfileStore: ApplicantProfileStore
    private let dataStore: InterviewDataStore
    private(set) var artifacts = OnboardingArtifacts()
    private(set) var applicantProfileJSON: JSON?
    private(set) var skeletonTimelineJSON: JSON?

    // MARK: - Checkpoint Dependencies (merged from OnboardingCheckpointManager)

    private let checkpoints: Checkpoints

    private(set) var preferences: OnboardingPreferences
    var latestReasoningSummary: String?
    private(set) var isProcessing = false
    private(set) var isActive = false
    private(set) var pendingExtraction: OnboardingPendingExtraction?
    private(set) var lastError: String?
    private(set) var pendingPhaseAdvanceRequest: OnboardingPhaseAdvanceRequest?
    private var orchestrator: InterviewOrchestrator?
    private var phaseAdvanceContinuationId: UUID?
    private var phaseAdvanceBlockCache: PhaseAdvanceBlockCache?
    private var toolQueueEntries: [UUID: ToolQueueEntry] = [:]
    private var developerMessages: [String] = []
    private var pendingExtractionProgressBuffer: [ExtractionProgressUpdate] = []
    private(set) var pendingStreamingStatus: String?
    private var reasoningSummaryClearTask: Task<Void, Never>?
    var onModelAvailabilityIssue: ((String) -> Void)?
    private(set) var objectiveStatuses: [String: ObjectiveStatus] = [:]
    private let ledgerDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
    private var objectiveStatusObservers: [(ObjectiveStatusUpdate) -> Void] = []

    private struct ToolQueueEntry {
        let tokenId: UUID
        let callId: String
        let toolName: String
        let status: String
        let requestedInput: String
        let enqueuedAt: Date
    }

    // MARK: - Objective Ledger and Developer Messages

    private func phasesThrough(_ phase: InterviewPhase) -> [InterviewPhase] {
        switch phase {
        case .phase1CoreFacts:
            return [.phase1CoreFacts]
        case .phase2DeepDive:
            return [.phase1CoreFacts, .phase2DeepDive]
        case .phase3WritingCorpus:
            return [.phase1CoreFacts, .phase2DeepDive, .phase3WritingCorpus]
        case .complete:
            return [.phase1CoreFacts, .phase2DeepDive, .phase3WritingCorpus]
        }
    }

    func registerObjectivesForCurrentPhase() async {
        let session = await interviewState.currentSession()
        for phase in phasesThrough(session.phase) {
            await interviewState.registerObjectives(ObjectiveCatalog.objectives(for: phase))
        }
        await refreshObjectiveStatuses()
    }

    func recordObjectiveStatus(
        _ id: String,
        status: ObjectiveStatus,
        source: String,
        details: [String: String]? = nil
    ) {
        Task {
            await interviewState.updateObjective(
                id: id,
                status: status,
                source: source,
                details: details
            )
            await refreshObjectiveStatuses()
        }
        objectiveStatuses[id] = status
        enqueueDeveloperMessage(objectiveStatusMessage(id: id, status: status, source: source, details: details))
        notifyObjectiveObservers(id: id, status: status, source: source, details: details)
        if id == "contact_photo_collected" || id == "contact_data_validated" || id == "contact_data_collected" {
            Task { await self.evaluateApplicantProfileObjective(trigger: "objective_\(id)") }
        }
    }

    private func objectiveStatusMessage(
        id: String,
        status: ObjectiveStatus,
        source: String,
        details: [String: String]?
    ) -> String {
        let label = objectiveLabel(for: id)
        let timestamp = ledgerDateFormatter.string(from: Date())
        var components: [String] = ["Objective update", label, "status=\(status.rawValue)", "source=\(source)", "at=\(timestamp)"]
        if let details, !details.isEmpty {
            let detailString = details.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "; ")
            components.append("details={\(detailString)}")
        }
        return components.joined(separator: " | ")
    }

    private func objectiveLabel(for id: String) -> String {
        for phase in [InterviewPhase.phase1CoreFacts, .phase2DeepDive, .phase3WritingCorpus] {
            if let descriptor = ObjectiveCatalog.objectives(for: phase).first(where: { $0.id == id }) {
                return descriptor.label
            }
        }
        return id
    }

    func addDeveloperStatus(_ message: String) {
        enqueueDeveloperMessage(message)
    }

    func registerToolWait(tokenId: UUID, toolName: String, callId: String, message: String?) {
        let entry = ToolQueueEntry(
            tokenId: tokenId,
            callId: callId,
            toolName: toolName,
            status: "waiting_for_user",
            requestedInput: requestedInputDescription(for: toolName, override: message),
            enqueuedAt: Date()
        )
        toolQueueEntries[tokenId] = entry
        let message = "Developer status: Tool \(toolName) is waiting\n\nDetails:\n• status: \(entry.status)\n• call_id: \(callId)\n• requested_input: \(entry.requestedInput)\n• enqueued_at: \(ledgerDateFormatter.string(from: entry.enqueuedAt))\n\nInstruction: Pause until the coordinator sends another status update."
        enqueueDeveloperMessage(message)
        enqueueDeveloperMessage(toolQueueSummary())
    }

    func clearToolWait(tokenId: UUID, outcome: String) {
        guard let entry = toolQueueEntries.removeValue(forKey: tokenId) else { return }
        enqueueDeveloperMessage("Developer status: Tool \(entry.toolName) finished\n\nDetails:\n• call_id: \(entry.callId)\n• outcome: \(outcome)")
        enqueueDeveloperMessage(toolQueueSummary())
    }

    func drainDeveloperMessages() -> [String] {
        if developerMessages.isEmpty { return [] }
        let messages = developerMessages
        developerMessages.removeAll()
        messages.forEach { Logger.info("📤 Developer message to LLM: \($0)", category: .ai) }
        return messages
    }

    private func enqueueDeveloperMessage(_ message: String) {
        guard !message.isEmpty else { return }
        developerMessages.append(message)
    }

    private func enqueueDeveloperStatus(from template: DeveloperMessageTemplates.Message) {
        let trimmedDetails = template.details.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let payload = template.payload

        var payloadText: String?
        if let payload, payload != .null {
            payloadText = payload.rawString(options: [.sortedKeys]) ?? payload.description
        }

        let readableDetails = trimmedDetails
            .sorted { $0.key < $1.key }
            .map { "• \($0.key): \($0.value)" }
            .joined(separator: "\n")

        var metadata = trimmedDetails
        if let payloadText {
            metadata["payload"] = payloadText
        }

        Logger.log(.info, "📤 Developer status queued: \(template.title)", category: .ai, metadata: metadata)

        var message = "Developer status: \(template.title)"
        if !readableDetails.isEmpty {
            message += "\n\nDetails:\n\(readableDetails)"
        }
        if let payloadText {
            message += "\n\nPayload:\n\(payloadText)"
        }

        enqueueDeveloperMessage(message)
    }

    func addObjectiveStatusObserver(_ observer: @escaping (ObjectiveStatusUpdate) -> Void) {
        objectiveStatusObservers.append(observer)
    }

    private func notifyObjectiveObservers(
        id: String,
        status: ObjectiveStatus,
        source: String,
        details: [String: String]?
    ) {
        guard !objectiveStatusObservers.isEmpty else { return }
        let update = ObjectiveStatusUpdate(
            id: id,
            status: status,
            source: source,
            details: details
        )
        objectiveStatusObservers.forEach { $0(update) }
    }

    private func toolQueueSummary() -> String {
        guard !toolQueueEntries.isEmpty else {
            return "Developer status: Tool queue empty"
        }
        let entries = toolQueueEntries.values.sorted { $0.enqueuedAt < $1.enqueuedAt }
        let detail = entries.enumerated().map { index, entry in
            "\(index + 1). \(entry.toolName) (status: \(entry.status), call_id: \(entry.callId)) → \(entry.requestedInput)"
        }.joined(separator: "\n")
        return "Developer status: Tool queue snapshot\n\n\(detail)"
    }

    private func requestedInputDescription(for toolName: String, override: String?) -> String {
        if let override, !override.isEmpty {
            return override
        }
        switch toolName {
        case "get_user_option":
            return "Awaiting user choice selection"
        case "get_user_upload":
            if let request = toolRouter.pendingUploadRequests.first {
                return "Upload requested: \(request.metadata.title)"
            }
            return "Awaiting file upload"
        case "get_macos_contact_card":
            return "Awaiting macOS Contacts permission"
        case "get_applicant_profile":
            if let intake = toolRouter.pendingApplicantProfileIntake {
                switch intake.mode {
                case .manual(let source):
                    return source == .contacts ? "Review imported contact details" : "Manual profile entry"
                case .urlEntry:
                    return "Awaiting profile URL submission"
                case .loading:
                    return "Fetching contact information"
                case .options:
                    return "Awaiting intake option selection"
                }
            }
            if toolRouter.pendingApplicantProfileRequest != nil {
                return "Applicant profile validation review"
            }
            return "Applicant profile intake"
        case "submit_for_validation":
            if toolRouter.pendingApplicantProfileRequest != nil {
                return "Confirm applicant profile data"
            }
            if let validation = toolRouter.pendingValidationPrompt {
                return "Review \(validation.dataType) data"
            }
            return "Validation review"
        case "extract_document":
            return "Processing uploaded document"
        default:
            return "Awaiting user action"
        }
    }

    init(
        chatTranscriptStore: ChatTranscriptStore,
        toolRouter: OnboardingToolRouter,
        applicantProfileStore: ApplicantProfileStore,
        dataStore: InterviewDataStore,
        checkpoints: Checkpoints,
        wizardTracker: WizardProgressTracker,
        phaseRegistry: PhaseScriptRegistry,
        interviewState: InterviewState,
        openAIService: OpenAIService?,
        preferences: OnboardingPreferences = OnboardingPreferences()
    ) {
        self.chatTranscriptStore = chatTranscriptStore
        self.toolRouter = toolRouter
        self.applicantProfileStore = applicantProfileStore
        self.dataStore = dataStore
        self.checkpoints = checkpoints
        self.wizardTracker = wizardTracker
        self.phaseRegistry = phaseRegistry
        self.interviewState = interviewState
        self.openAIService = openAIService
        self.toolRegistry = ToolRegistry()
        self.toolExecutor = ToolExecutor(registry: toolRegistry)
        self.preferences = preferences
    }

    var messages: [OnboardingMessage] {
        chatTranscriptStore.messages
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

    var pendingUploadRequests: [OnboardingUploadRequest] {
        toolRouter.pendingUploadRequests
    }

    var uploadedItems: [OnboardingUploadedItem] {
        toolRouter.uploadedItems
    }

    var pendingSectionToggleRequest: OnboardingSectionToggleRequest? {
        toolRouter.pendingSectionToggleRequest
    }

    var wizardStep: OnboardingWizardStep { wizardTracker.currentStep }

    var completedWizardSteps: Set<OnboardingWizardStep> { wizardTracker.completedSteps }

    var wizardStepStatuses: [OnboardingWizardStep: OnboardingWizardStepStatus] { wizardTracker.stepStatuses }

    // MARK: - Chat helpers

    func appendUserMessage(_ text: String) {
        Logger.info("💬 User message: \(text)", category: .ai)
        chatTranscriptStore.appendUserMessage(text)
    }

    @discardableResult
    func appendAssistantMessage(_ text: String, reasoningExpected: Bool = false) -> UUID {
        Logger.info("🤖 Assistant message: \(text)", category: .ai)
        return chatTranscriptStore.appendAssistantMessage(text, reasoningExpected: reasoningExpected)
    }

    @discardableResult
    func beginAssistantStream(initialText: String = "", reasoningExpected: Bool = false) -> UUID {
        if !initialText.isEmpty {
            Logger.info("🤖 Assistant stream started: \(initialText)", category: .ai)
        }
        return chatTranscriptStore.beginAssistantStream(initialText: initialText, reasoningExpected: reasoningExpected)
    }

    func updateAssistantStream(id: UUID, text: String) {
        chatTranscriptStore.updateAssistantStream(id: id, text: text)
    }

    func finalizeAssistantStream(id: UUID, text: String) -> TimeInterval {
        Logger.info("🤖 Assistant stream finalized: \(text)", category: .ai)
        let elapsed = chatTranscriptStore.finalizeAssistantStream(id: id, text: text)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            clearLatestReasoningSummary()
        }
        return elapsed
    }

    func updateReasoningSummary(_ summary: String, for messageId: UUID, isFinal: Bool) {
        chatTranscriptStore.updateReasoningSummary(summary, for: messageId, isFinal: isFinal)
    }

    func finalizeReasoningSummaries(for messageIds: [UUID]) {
        chatTranscriptStore.finalizeReasoningSummariesIfNeeded(for: messageIds)
    }

    func updateLatestReasoningSummary(_ summary: String?, isFinal: Bool) {
        reasoningSummaryClearTask?.cancel()
        reasoningSummaryClearTask = nil

        guard let trimmed = summary?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            latestReasoningSummary = nil
            return
        }

        latestReasoningSummary = trimmed

        guard isFinal else { return }

        reasoningSummaryClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(6 * 1_000_000_000))
            await MainActor.run {
                guard let self else { return }
                self.latestReasoningSummary = nil
                self.reasoningSummaryClearTask = nil
            }
        }
    }

    func clearLatestReasoningSummary() {
        reasoningSummaryClearTask?.cancel()
        reasoningSummaryClearTask = nil
        latestReasoningSummary = nil
    }

    func notifyInvalidModel(id: String) {
        Logger.warning("⚠️ Invalid model id reported: \(id)", category: .ai)
        onModelAvailabilityIssue?(id)
    }

    func evaluateApplicantProfileObjective(trigger: String = "evaluation") async {
        let currentStatus = await interviewState.objectiveStatus(for: "applicant_profile")

        guard applicantProfileJSON != nil else {
            if currentStatus != .pending {
                recordObjectiveStatus(
                    "applicant_profile",
                    status: .pending,
                    source: "system_evaluated",
                    details: ["reason": "missing_profile", "trigger": trigger]
                )
            }
            return
        }

        let photoStatus = await interviewState.objectiveStatus(for: "contact_photo_collected")
        let photoSatisfied = (photoStatus == .completed) || (photoStatus == .skipped)

        let validationStatus = await interviewState.objectiveStatus(for: "contact_data_validated")
        let validationSatisfied = (validationStatus == nil) || (validationStatus == .completed)

        if photoSatisfied && validationSatisfied {
            if currentStatus != .completed {
                recordObjectiveStatus(
                    "applicant_profile",
                    status: .completed,
                    source: "system_evaluated",
                    details: [
                        "reason": "profile_ready",
                        "trigger": trigger
                    ]
                )
            }
        } else {
            if currentStatus != .inProgress {
                var detail: [String: String] = ["trigger": trigger]
                detail["photo_status"] = photoStatus?.rawValue ?? "missing"
                detail["validation_status"] = validationStatus?.rawValue ?? "missing"
                recordObjectiveStatus(
                    "applicant_profile",
                    status: .inProgress,
                    source: "system_evaluated",
                    details: detail
                )
            }
        }
    }

    func setStreamingStatus(_ status: String?) {
        pendingStreamingStatus = status
    }

    func appendSystemMessage(_ text: String) {
        Logger.info("📢 System message: \(text)", category: .ai)
        chatTranscriptStore.appendSystemMessage(text)
    }

    func resetTranscript() {
        chatTranscriptStore.reset()
        toolRouter.reset()
        pendingStreamingStatus = nil
        clearLatestReasoningSummary()
    }

    func transcriptExportString() -> String {
        chatTranscriptStore.formattedTranscript()
    }

    // MARK: - Preferences

    func setPreferredDefaults(modelId: String, backend: LLMFacade.Backend, webSearchAllowed: Bool) {
        preferences.preferredModelId = modelId
        preferences.preferredBackend = backend
        preferences.allowWebSearch = webSearchAllowed
    }

    func setWritingAnalysisConsent(_ allowed: Bool) {
        preferences.allowWritingAnalysis = allowed
    }

    // MARK: - Wizard Progress

    func setWizardStep(_ step: OnboardingWizardStep) {
        wizardTracker.setStep(step)
    }

    func updateWaitingState(_ waiting: InterviewSession.Waiting?) {
        wizardTracker.updateWaitingState(waiting)
    }

    func syncWizardProgress(from session: InterviewSession) {
        wizardTracker.syncProgress(from: session)
    }

    func resetWizard() {
        wizardTracker.reset()
    }

    func buildSystemPrompt(for session: InterviewSession) -> String {
        phaseRegistry.buildSystemPrompt(for: session)
    }

    // MARK: - Session & Objectives

    func currentSession() async -> InterviewSession {
        await interviewState.currentSession()
    }

    func missingObjectives() async -> [String] {
        await interviewState.missingObjectives()
    }

    func nextPhase() async -> InterviewPhase? {
        await interviewState.nextPhase()
    }

    func advancePhase() async -> InterviewPhase? {
        await interviewState.advanceToNextPhase()
        let session = await interviewState.currentSession()
        applyWizardProgress(from: session)
        phaseAdvanceBlockCache = nil
        await registerObjectivesForCurrentPhase()
        return session.phase
    }

    func updateObjectiveStatus(objectiveId: String, status: String) async throws -> JSON {
        let normalized = status.lowercased()
        let ledgerStatus: ObjectiveStatus

        switch normalized {
        case "completed":
            await interviewState.completeObjective(objectiveId, source: "llm_proposed", notes: nil)
            ledgerStatus = .completed
        case "pending", "reset":
            await interviewState.resetObjective(objectiveId)
            ledgerStatus = .pending
        case "in_progress":
            await interviewState.beginObjective(objectiveId, source: "llm_proposed", notes: nil)
            ledgerStatus = .inProgress
        case "skipped":
            await interviewState.skipObjective(objectiveId, reason: "llm_proposed")
            ledgerStatus = .skipped
        default:
            throw ToolError.invalidParameters("Unsupported status: \(status)")
        }

        recordObjectiveStatus(
            objectiveId,
            status: ledgerStatus,
            source: "llm_proposed",
            details: ["requested_status": normalized]
        )

        let session = await interviewState.currentSession()
        applyWizardProgress(from: session)
        phaseAdvanceBlockCache = nil

        var response = JSON()
        response["status"].string = "ok"
        response["objective"].string = objectiveId
        response["state"].string = ledgerStatus.rawValue
        return response
    }

    // MARK: - Checkpoints (merged from OnboardingCheckpointManager)

    func hasRestorableCheckpoint() async -> Bool {
        await checkpoints.hasCheckpoint()
    }

    func restoreCheckpoint() async -> (InterviewSession, JSON?, JSON?, [String]?, [ObjectiveEntry])? {
        await checkpoints.restoreLatest()
    }

    func saveCheckpoint(
        applicantProfile: JSON?,
        skeletonTimeline: JSON?,
        enabledSections: [String]?
    ) async {
        let session = await interviewState.currentSession()
        await checkpoints.save(
            from: session,
            applicantProfile: applicantProfile,
            skeletonTimeline: skeletonTimeline,
            enabledSections: enabledSections.flatMap { $0.isEmpty ? nil : $0 }
        )
        Logger.debug("💾 Checkpoint saved (phase: \(session.phase.rawValue))", category: .ai)
    }

    func clearCheckpoints() async {
        await checkpoints.clear()
        Logger.debug("🗑️ Checkpoints cleared", category: .ai)
    }

    // MARK: - Data Store (merged from OnboardingDataStoreManager)

    /// Stores the applicant profile JSON and syncs it to SwiftData.
    func storeApplicantProfile(_ json: JSON) {
        if let existing = applicantProfileJSON, existing == json { return }
        applicantProfileJSON = json
        let draft = ApplicantProfileDraft(json: json)
        let profile = applicantProfileStore.currentProfile()
        draft.apply(to: profile, replaceMissing: false)
        applicantProfileStore.save(profile)
        artifacts.applicantProfile = json

        Logger.debug("📝 ApplicantProfile stored: \(json.dictionaryValue.keys.joined(separator: ", "))", category: .ai)
    }

    /// Updates the applicant profile image and syncs to SwiftData.
    func storeApplicantProfileImage(data: Data, mimeType: String?) {
        let profile = applicantProfileStore.currentProfile()
        profile.pictureData = data
        profile.pictureMimeType = mimeType
        applicantProfileStore.save(profile)

        var json = applicantProfileJSON ?? JSON()
        json["image"].string = data.base64EncodedString()
        if let mimeType {
            json["image_mime_type"].string = mimeType
        }
        applicantProfileJSON = json
        artifacts.applicantProfile = json

        Logger.debug("📸 Applicant profile image updated (\(data.count) bytes, mime: \(mimeType ?? "unknown"))", category: .ai)
    }

    /// Stores the skeleton timeline JSON.
    func storeSkeletonTimeline(_ json: JSON) {
        let normalized = TimelineCardAdapter.normalizedTimeline(json)
        skeletonTimelineJSON = normalized
        artifacts.skeletonTimeline = normalized

        Logger.debug("📅 Skeleton timeline stored", category: .ai)
    }

    /// Stores an artifact record keyed by its identifier.
    func storeArtifactRecord(_ artifact: JSON) {
        guard artifact != .null else { return }

        guard let artifactId = artifact["id"].string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !artifactId.isEmpty else {
            Logger.warning("⚠️ Artifact record missing id; entry skipped.", category: .ai)
            return
        }

        let metadata = artifact["metadata"]
        let purpose = metadata["purpose"].string?.lowercased()
        let extractedContent = artifact["extracted_content"].stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldEnforceTimelineTools = (purpose == "resume_timeline") && !extractedContent.isEmpty
        artifacts.artifactRecords.removeAll { $0["id"].stringValue == artifactId }
        artifacts.artifactRecords.append(artifact)

        let sha = artifact["sha256"].stringValue
        Logger.debug("📦 Artifact record stored (id: \(artifactId), sha256: \(sha))", category: .ai)
        let message = DeveloperMessageTemplates.artifactStored(artifact: artifact)
        enqueueDeveloperStatus(from: message)

        if shouldEnforceTimelineTools {
            Task { [weak self] in
                guard let self else { return }
                await self.orchestrator?.scheduleTimelineToolEnforcement()
            }
        }
    }

    func artifactRecord(id: String) -> JSON? {
        artifacts.artifactRecords.first { $0["id"].stringValue == id }
    }

    func rawArtifactFile(for artifactId: String) -> (data: Data, mimeType: String, filename: String, sha256: String?)? {
        guard let record = artifactRecord(id: artifactId) else {
            return nil
        }

        let metadata = record["metadata"]
        if let inlineBase64 = metadata["inline_base64"].string,
           let data = Data(base64Encoded: inlineBase64) {
            let mimeType = record["content_type"].stringValue.isEmpty
                ? "application/octet-stream"
                : record["content_type"].stringValue
            let filename = metadata["source_filename"].string ??
                record["filename"].string ??
                "artifact.\(record["content_type"].stringValue.split(separator: "/").last ?? "dat")"
            return (data, mimeType, filename, record["sha256"].string)
        } else if metadata["inline_base64"].string != nil {
            Logger.warning("⚠️ Inline base64 payload for artifact \(artifactId) could not be decoded.", category: .ai)
        }

        let urlString = metadata["source_file_url"].string ?? metadata["source_path"].string
        guard
            let urlString,
            let url = URL(string: urlString)
        else {
            Logger.warning("⚠️ Artifact \(artifactId) missing source_file_url metadata.", category: .ai)
            return nil
        }

        guard let data = try? Data(contentsOf: url) else {
            Logger.warning("⚠️ Failed to load artifact \(artifactId) at \(url).", category: .ai)
            return nil
        }

        let mimeType: String = {
            if let explicit = record["content_type"].string, !explicit.isEmpty {
                return explicit
            }
            if #available(macOS 12.0, *) {
                return UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            }
            return "application/octet-stream"
        }()

        let filename = metadata["source_filename"].string ??
            record["filename"].string ??
            url.lastPathComponent

        return (data, mimeType, filename, record["sha256"].string)
    }

    /// Stores a knowledge card, deduplicating by ID if present.
    func storeKnowledgeCard(_ card: JSON) {
        guard card != .null else { return }

        if let identifier = card["id"].string, !identifier.isEmpty {
            artifacts.knowledgeCards.removeAll { $0["id"].stringValue == identifier }
        }
        artifacts.knowledgeCards.append(card)

        Logger.debug("🃏 Knowledge card stored (id: \(card["id"].stringValue))", category: .ai)
    }

    /// Updates the enabled sections list.
    func updateEnabledSections(_ sections: [String]) {
        let normalizedKeys = sections.compactMap { ExperienceSectionKey.fromOnboardingIdentifier($0)?.rawValue }
        var seen: Set<String> = []
        let deduped = normalizedKeys.filter { seen.insert($0).inserted }
        artifacts.enabledSections = deduped
        Logger.debug("🧩 Enabled sections updated: \(artifacts.enabledSections.joined(separator: ", "))", category: .ai)
    }

    /// Loads persisted artifacts from the data store.
    func loadPersistedArtifacts() async {
        // Load artifact records
        let records = await dataStore.list(dataType: "artifact_record")
        var deduped: [JSON] = []
        var seen: Set<String> = []
        for record in records {
            let artifactId = record["id"].stringValue
            guard !artifactId.isEmpty else {
                Logger.warning("⚠️ Skipping persisted artifact without id.", category: .ai)
                continue
            }
            guard !seen.contains(artifactId) else { continue }
            seen.insert(artifactId)
            deduped.append(record)
        }
        artifacts.artifactRecords = deduped

        // Load knowledge cards
        let storedKnowledgeCards = await dataStore.list(dataType: "knowledge_card")
        artifacts.knowledgeCards = storedKnowledgeCards

        Logger.debug("📂 Loaded \(deduped.count) artifact records, \(storedKnowledgeCards.count) knowledge cards", category: .ai)
    }

    /// Clears all artifact state (for interview reset).
    func clearArtifacts() {
        applicantProfileJSON = nil
        skeletonTimelineJSON = nil
        artifacts.applicantProfile = nil
        artifacts.skeletonTimeline = nil
        artifacts.artifactRecords = []
        artifacts.enabledSections = []
        artifacts.knowledgeCards = []

        Logger.debug("🗑️ All artifacts cleared", category: .ai)
        pendingStreamingStatus = nil
    }

    /// Removes all persisted onboarding data from disk.
    func resetStore() async {
        await dataStore.reset()
        Logger.debug("🧹 Interview data store cleared", category: .ai)
    }

    // MARK: - Choice Prompts

    func presentChoicePrompt(_ prompt: OnboardingChoicePrompt, continuationId: UUID) {
        toolRouter.presentChoicePrompt(prompt, continuationId: continuationId)
    }

    func clearChoicePrompt(continuationId: UUID) {
        toolRouter.clearChoicePrompt(continuationId: continuationId)
    }

    func resolveChoice(selectionIds: [String]) -> (UUID, JSON)? {
        toolRouter.resolveChoice(selectionIds: selectionIds)
    }

    func cancelChoicePrompt(reason: String) -> (UUID, JSON)? {
        toolRouter.cancelChoicePrompt(reason: reason)
    }

    // MARK: - Validation Prompts

    func presentValidationPrompt(_ prompt: OnboardingValidationPrompt, continuationId: UUID) {
        // Store skeleton timeline data when it's submitted for validation
        if prompt.dataType == "skeleton_timeline" {
            storeSkeletonTimeline(prompt.payload)
            Logger.info("📝 Stored skeleton timeline from validation submission", category: .ai)
        }

        toolRouter.presentValidationPrompt(prompt, continuationId: continuationId)
    }

    func clearValidationPrompt(continuationId: UUID) {
        toolRouter.clearValidationPrompt(continuationId: continuationId)
    }

    func submitValidationResponse(
        status: String,
        updatedData: JSON?,
        changes: JSON?,
        notes: String?
    ) -> (UUID, JSON)? {
        toolRouter.submitValidationResponse(
            status: status,
            updatedData: updatedData,
            changes: changes,
            notes: notes
        )
    }

    func cancelValidation(reason: String) -> (UUID, JSON)? {
        toolRouter.cancelValidation(reason: reason)
    }

    // MARK: - Applicant Profile Validation

    func presentApplicantProfileRequest(_ request: OnboardingApplicantProfileRequest, continuationId: UUID) {
        toolRouter.presentApplicantProfileRequest(request, continuationId: continuationId)
    }

    func clearApplicantProfileRequest(continuationId: UUID) {
        toolRouter.clearApplicantProfileRequest(continuationId: continuationId)
    }

    func resolveApplicantProfile(with draft: ApplicantProfileDraft) -> (UUID, JSON)? {
        toolRouter.resolveApplicantProfile(with: draft)
    }

    func rejectApplicantProfile(reason: String) -> (UUID, JSON)? {
        toolRouter.rejectApplicantProfile(reason: reason)
    }

    // MARK: - Applicant Profile Intake

    func presentApplicantProfileIntake(continuationId: UUID) {
        toolRouter.presentApplicantProfileIntake(continuationId: continuationId)
    }

    func resetApplicantProfileIntakeToOptions() {
        toolRouter.resetApplicantProfileIntakeToOptions()
    }

    func beginApplicantProfileManualEntry() {
        toolRouter.beginApplicantProfileManualEntry()
    }

    func beginApplicantProfileURL() {
        toolRouter.beginApplicantProfileURL()
    }

    func beginApplicantProfileUpload() -> (request: OnboardingUploadRequest, continuationId: UUID)? {
        toolRouter.beginApplicantProfileUpload()
    }

    func beginApplicantProfileContactsFetch() {
        toolRouter.beginApplicantProfileContactsFetch()
    }

    func submitApplicantProfileURL(_ urlString: String) -> (UUID, JSON)? {
        toolRouter.submitApplicantProfileURL(urlString)
    }

    func completeApplicantProfileDraft(_ draft: ApplicantProfileDraft, source: OnboardingApplicantProfileIntakeState.Source) -> (UUID, JSON)? {
        toolRouter.completeApplicantProfileDraft(draft, source: source)
    }

    func cancelApplicantProfileIntake(reason: String) -> (UUID, JSON)? {
        toolRouter.cancelApplicantProfileIntake(reason: reason)
    }

    // MARK: - Uploads

    func presentUploadRequest(_ request: OnboardingUploadRequest, continuationId: UUID) {
        toolRouter.presentUploadRequest(request, continuationId: continuationId)
    }

    func completeUpload(id: UUID, fileURLs: [URL]) async -> (UUID, JSON)? {
        await toolRouter.completeUpload(id: id, fileURLs: fileURLs)
    }

    func completeUpload(id: UUID, link: URL) async -> (UUID, JSON)? {
        await toolRouter.completeUpload(id: id, link: link)
    }

    func skipUpload(id: UUID) async -> (UUID, JSON)? {
        await toolRouter.skipUpload(id: id)
    }

    func cancelUpload(id: UUID, reason: String?) async -> (UUID, JSON)? {
        await toolRouter.cancelUpload(id: id, reason: reason)
    }

    func cancelPendingUpload(reason: String?) async -> (UUID, JSON)? {
        await toolRouter.cancelPendingUpload(reason: reason)
    }

    // MARK: - Section Toggle Handling

    func presentSectionToggle(_ request: OnboardingSectionToggleRequest, continuationId: UUID) {
        toolRouter.presentSectionToggle(request, continuationId: continuationId)
    }

    func resolveSectionToggle(enabled: [String]) -> (UUID, JSON)? {
        if let result = toolRouter.resolveSectionToggle(enabled: enabled) {
            updateEnabledSections(enabled)
            return result
        }
        return nil
    }

    func rejectSectionToggle(reason: String) -> (UUID, JSON)? {
        toolRouter.rejectSectionToggle(reason: reason)
    }

    // MARK: - Continuations

    func resumeToolContinuation(id: UUID, payload: JSON) async {
        isProcessing = true
        await orchestrator?.resumeToolContinuation(id: id, payload: payload)
    }

    func setProcessingState(_ processing: Bool) {
        isProcessing = processing
    }

    // MARK: - Phase Advance Handling

    func hasActivePhaseAdvanceRequest() -> Bool {
        pendingPhaseAdvanceRequest != nil
    }

    func currentPhaseAdvanceAwaitingPayload() -> JSON? {
        guard let request = pendingPhaseAdvanceRequest else { return nil }
        return buildAwaitingPayload(for: request)
    }

    func cachedPhaseAdvanceBlockedResponse(missing: [String], overrides: [String]) async -> JSON? {
        guard let cache = phaseAdvanceBlockCache else { return nil }
        return cache.matches(missing: missing, overrides: overrides) ? cache.response : nil
    }

    func cachePhaseAdvanceBlockedResponse(missing: [String], overrides: [String], response: JSON) async {
        phaseAdvanceBlockCache = PhaseAdvanceBlockCache(
            missing: missing,
            overrides: overrides,
            response: response
        )
    }

    func logPhaseAdvanceEvent(
        status: String,
        overrides: [String],
        missing: [String],
        reason: String?,
        userDecision: String?,
        advancedTo: InterviewPhase?,
        currentPhase: InterviewPhase
    ) async {
        var metadata: [String: String] = [
            "status": status,
            "overrides": overrides.joined(separator: ","),
            "missing": missing.joined(separator: ","),
            "current_phase": currentPhase.rawValue
        ]
        if let reason, !reason.isEmpty {
            metadata["reason"] = reason
        }
        if let userDecision {
            metadata["decision"] = userDecision
        }
        if let advancedTo {
            metadata["advanced_to"] = advancedTo.rawValue
            metadata["next_phase"] = advancedTo.rawValue
        }
        Logger.info("🎯 Phase advance \(status)", category: .ai, metadata: metadata)
    }

    func presentPhaseAdvanceRequest(_ request: OnboardingPhaseAdvanceRequest, continuationId: UUID) {
        phaseAdvanceBlockCache = nil
        pendingPhaseAdvanceRequest = request
        phaseAdvanceContinuationId = continuationId
        isProcessing = false
        updateWaitingState(.validation)
        Task { [request] in
            await logPhaseAdvanceEvent(
                status: "awaiting_user_approval",
                overrides: request.proposedOverrides,
                missing: request.missingObjectives,
                reason: request.reason,
                userDecision: nil,
                advancedTo: request.nextPhase,
                currentPhase: request.currentPhase
            )
        }
    }

    func approvePhaseAdvanceRequest() async {
        guard let continuationId = phaseAdvanceContinuationId else { return }
        let request = pendingPhaseAdvanceRequest
        pendingPhaseAdvanceRequest = nil
        phaseAdvanceContinuationId = nil
        updateWaitingState(nil)
        isProcessing = true

        let newPhase = await advancePhase()
        var payload = JSON()
        payload["status"].string = "approved"
        if let newPhase {
            payload["advanced_to"].string = newPhase.rawValue
        }

        await persistCheckpoint()
        if let request {
            await logPhaseAdvanceEvent(
                status: "approved",
                overrides: request.proposedOverrides,
                missing: request.missingObjectives,
                reason: request.reason,
                userDecision: "approved",
                advancedTo: newPhase,
                currentPhase: request.currentPhase
            )
        }
        await orchestrator?.resumeToolContinuation(id: continuationId, payload: payload)
    }

    func denyPhaseAdvanceRequest(feedback: String?) async {
        guard let continuationId = phaseAdvanceContinuationId else { return }
        let request = pendingPhaseAdvanceRequest
        pendingPhaseAdvanceRequest = nil
        phaseAdvanceContinuationId = nil
        updateWaitingState(nil)
        isProcessing = true

        var payload = JSON()
        if let feedback, !feedback.isEmpty {
            payload["status"].string = "denied_with_feedback"
            payload["feedback"].string = feedback
        } else {
            payload["status"].string = "denied"
        }

        phaseAdvanceBlockCache = PhaseAdvanceBlockCache(
            missing: request?.missingObjectives ?? [],
            overrides: request?.proposedOverrides ?? [],
            response: payload
        )
        if let request {
            let decision = payload["status"].stringValue
            await logPhaseAdvanceEvent(
                status: decision,
                overrides: request.proposedOverrides,
                missing: request.missingObjectives,
                reason: request.reason,
                userDecision: decision,
                advancedTo: nil,
                currentPhase: request.currentPhase
            )
        }
        await orchestrator?.resumeToolContinuation(id: continuationId, payload: payload)
    }

    // MARK: - Interview Lifecycle

    func startInterview(modelId: String, backend: LLMFacade.Backend, resumeExisting: Bool) async {
        guard backend == .openAI else {
            updateLastError("Only the OpenAI backend is supported for onboarding interviews.")
            return
        }

        guard let openAIService else {
            updateLastError("OpenAI API key is not configured.")
            return
        }

        guard isActive == false else {
            Logger.debug("startInterview called while interview is already active; ignoring request.")
            return
        }

        updateLastError(nil)
        resetTransientState()

        let restoredFromCheckpoint = await prepareStateForStart(resumeExisting: resumeExisting)
        await registerObjectivesForCurrentPhase()

        let currentSession = await interviewState.currentSession()
        let prompt = buildSystemPrompt(for: currentSession)
        orchestrator = makeOrchestrator(service: openAIService, systemPrompt: prompt)
        isActive = true
        isProcessing = true

        if !restoredFromCheckpoint {
            wizardTracker.setStep(.resumeIntake)
            Logger.debug("[WizardStep] Set to .resumeIntake (fresh start)")
        } else {
            Logger.debug("[WizardStep] After checkpoint restore: \(wizardStep)")
        }

        await orchestrator?.startInterview(modelId: modelId)
    }

    func sendMessage(_ text: String) async {
        guard isActive else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        appendUserMessage(trimmed)
        await orchestrator?.sendUserMessage(trimmed)
    }

    func resetInterview() {
        resetTransientState()
        updateLastError(nil)
        orchestrator = nil

        Task { await interviewState.restore(from: InterviewSession()) }
        Task { await loadPersistedArtifacts() }
        Task { await clearCheckpoints() }
    }

    func setExtractionStatus(_ status: OnboardingPendingExtraction?) {
        guard var status else {
            pendingExtraction = nil
            pendingExtractionProgressBuffer.removeAll()
            setStreamingStatus(nil)
            return
        }

        status.ensureProgressItems()
        if !pendingExtractionProgressBuffer.isEmpty {
            status.applyProgressUpdates(pendingExtractionProgressBuffer)
            pendingExtractionProgressBuffer.removeAll()
        }
        pendingExtraction = status

        // Clear the applicant profile intake card when extraction begins
        // This ensures the spinner can show during document processing
        if status.documentType == "resume" && pendingApplicantProfileIntake != nil {
            toolRouter.clearApplicantProfileIntake()
        }
    }

    func updateExtractionProgress(with update: ExtractionProgressUpdate) {
        if var extraction = pendingExtraction {
            extraction.applyProgressUpdate(update)
            pendingExtraction = extraction
        } else {
            pendingExtractionProgressBuffer.append(update)
        }
        updateStreamingStatusFromExtraction(update)
    }

    func updateLastError(_ message: String?) {
        lastError = message
    }

    func recordError(_ message: String) {
        lastError = message
        appendSystemMessage("⚠️ \(message)")
    }

    private func updateStreamingStatusFromExtraction(_ update: ExtractionProgressUpdate) {
        switch update.state {
        case .active:
            guard let message = streamingStatusMessage(for: update.stage, detail: update.detail) else { return }
            setStreamingStatus(message)
        case .completed:
            if update.stage == .assistantHandoff {
                setStreamingStatus(nil)
            }
        case .failed:
            setStreamingStatus(nil)
        case .pending:
            break
        }
    }

    private func streamingStatusMessage(for stage: ExtractionProgressStage, detail: String?) -> String? {
        let trimmed = detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch stage {
        case .fileAnalysis:
            if let trimmed, !trimmed.isEmpty {
                return ellipsizedStatusText(trimmed)
            }
            return "Analyzing document…"
        case .aiExtraction:
            if let trimmed, !trimmed.isEmpty {
                return ellipsizedStatusText(trimmed)
            }
            return "Extracting document text…"
        case .artifactSave:
            if let trimmed, !trimmed.isEmpty {
                return ellipsizedStatusText("Saving \(trimmed)")
            }
            return "Saving artifact…"
        case .assistantHandoff:
            return "Sending to assistant…"
        }
    }

    private func ellipsizedStatusText(_ text: String) -> String {
        if text.hasSuffix("…") || text.hasSuffix("...") {
            return text
        }
        return "\(text)…"
    }

    // Note: loadPersistedArtifacts() is already defined above in the Data Store section

    // MARK: - Internal Helpers

    private func prepareStateForStart(resumeExisting: Bool) async -> Bool {
        let restored: Bool
        if resumeExisting {
            await loadPersistedArtifacts()
            await interviewState.restore(from: InterviewSession())
            let didRestore = await restoreFromCheckpointIfAvailable()
            if !didRestore {
                await clearCheckpoints()
                clearArtifacts()
                await resetStore()
            }
            restored = didRestore
        } else {
            await clearCheckpoints()
            clearArtifacts()
            await resetStore()
            await interviewState.restore(from: InterviewSession())
            restored = false
        }
        await refreshObjectiveStatuses()
        return restored
    }

    private func restoreFromCheckpointIfAvailable() async -> Bool {
        guard let snapshot = await restoreCheckpoint() else {
            return false
        }

        let (session, profileJSON, timelineJSON, enabledSections, _) = snapshot
        await interviewState.restore(from: session)
        applyWizardProgress(from: session)

        // Restore data synchronously without triggering checkpoint saves
        if let profileJSON {
            applicantProfileJSON = profileJSON
            let draft = ApplicantProfileDraft(json: profileJSON)
            let profile = applicantProfileStore.currentProfile()
            draft.apply(to: profile, replaceMissing: false)
            applicantProfileStore.save(profile)
            artifacts.applicantProfile = profileJSON
            Logger.debug("📝 ApplicantProfile restored from checkpoint", category: .ai)
        }
        if let timelineJSON {
            skeletonTimelineJSON = timelineJSON
            artifacts.skeletonTimeline = timelineJSON
            Logger.debug("📅 Skeleton timeline restored from checkpoint", category: .ai)
        }
        if let enabledSections, !enabledSections.isEmpty {
            updateEnabledSections(enabledSections)
        }

        isProcessing = false
        await refreshObjectiveStatuses()
        return true
    }

    private func applyWizardProgress(from session: InterviewSession) {
        syncWizardProgress(from: session)
    }

    private func makeOrchestrator(
        service: OpenAIService,
        systemPrompt: String
    ) -> InterviewOrchestrator {

        let callbacks = InterviewOrchestrator.Callbacks(
            updateProcessingState: { [weak self] processing in
                guard let self else { return }
                await MainActor.run { self.isProcessing = processing }
            },
            emitAssistantMessage: { [weak self] text, reasoningExpected in
                guard let self else { return UUID() }
                return await MainActor.run {
                    let messageId = self.appendAssistantMessage(text, reasoningExpected: reasoningExpected)
                    // If we actually got assistant text, clear any "latest" dangling reasoning.
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                        self.clearLatestReasoningSummary()
                    }
                    return messageId
                }
            },
            beginStreamingAssistantMessage: { [weak self] initialText, reasoningExpected in
                guard let self else { return UUID() }
                return await MainActor.run {
                    self.beginAssistantStream(initialText: initialText, reasoningExpected: reasoningExpected)
                }
            },
            updateStreamingAssistantMessage: { [weak self] id, delta in
                guard let self else { return }
                _ = await MainActor.run { self.updateAssistantStream(id: id, text: delta) }
            },
            finalizeStreamingAssistantMessage: { [weak self] id, final in
                guard let self else { return }
                _ = await MainActor.run { self.finalizeAssistantStream(id: id, text: final) }
            },
            updateReasoningSummary: { [weak self] messageId, summary, isFinal in
                guard let self else { return }
                _ = await MainActor.run {
                    // Keep per-message reasoning paired AND surface the latest summary in the status bar.
                    self.updateReasoningSummary(summary, for: messageId, isFinal: isFinal)
                    self.updateLatestReasoningSummary(summary, isFinal: isFinal)
                }
            },
            finalizeReasoningSummaries: { [weak self] messageIds in
                guard let self else { return }
                _ = await MainActor.run {
                    self.finalizeReasoningSummaries(for: messageIds)
                }
            },
            updateStreamingStatus: { [weak self] status in
                guard let self else { return }
                await MainActor.run {
                    self.setStreamingStatus(status)
                }
            },
            handleWaitingState: { [weak self] waiting in
                guard let self else { return }
                await MainActor.run {
                    self.updateWaitingState(waiting)
                }
            },
            handleError: { [weak self] message in
                guard let self else { return }
                await MainActor.run {
                    self.recordError(message)
                }
            },
            storeApplicantProfile: { [weak self] json in
                guard let self else { return }
                await self.storeApplicantProfile(json)
            },
            storeSkeletonTimeline: { [weak self] json in
                guard let self else { return }
                await self.storeSkeletonTimeline(json)
            },
            storeArtifactRecord: { [weak self] artifact in
                guard let self else { return }
                await self.storeArtifactRecord(artifact)
            },
            storeKnowledgeCard: { [weak self] card in
                guard let self else { return }
                await self.storeKnowledgeCard(card)
            },
            setExtractionStatus: { [weak self] status in
                guard let self else { return }
                await MainActor.run { self.setExtractionStatus(status) }
            },
            updateExtractionProgress: { [weak self] update in
                guard let self else { return }
                await MainActor.run { self.updateExtractionProgress(with: update) }
            },
            persistCheckpoint: { [weak self] in
                guard let self else { return }
                await self.persistCheckpoint()
            },
            registerToolWait: { [weak self] tokenId, toolName, callId, message in
                guard let self else { return }
                await MainActor.run {
                    self.registerToolWait(tokenId: tokenId, toolName: toolName, callId: callId, message: message)
                }
            },
            clearToolWait: { [weak self] tokenId, outcome in
                guard let self else { return }
                await MainActor.run {
                    self.clearToolWait(tokenId: tokenId, outcome: outcome)
                }
            },
            handleInvalidModelId: { [weak self] modelId in
                guard let self else { return }
                await MainActor.run {
                    self.notifyInvalidModel(id: modelId)
                }
            },
           
        )

        return InterviewOrchestrator(
            client: service,
            state: interviewState,
            toolExecutor: toolExecutor,
            callbacks: callbacks,
            systemPrompt: systemPrompt
        )
    }

    private func storeApplicantProfile(_ json: JSON) async {
        // Store the applicant profile (call public synchronous version)
        if let existing = applicantProfileJSON, existing == json { return }
        applicantProfileJSON = json
        let draft = ApplicantProfileDraft(json: json)
        let profile = applicantProfileStore.currentProfile()
        draft.apply(to: profile, replaceMissing: false)
        applicantProfileStore.save(profile)
        artifacts.applicantProfile = json
        Logger.debug("📝 ApplicantProfile stored: \(json.dictionaryValue.keys.joined(separator: ", "))", category: .ai)

        await persistCheckpoint()
        recordObjectiveStatus(
            "applicant_profile",
            status: .inProgress,
            source: "system_persist",
            details: ["reason": "persisted"]
        )
        await evaluateApplicantProfileObjective(trigger: "profile_persisted")
    }

    private func storeSkeletonTimeline(_ json: JSON) async {
        let normalized = TimelineCardAdapter.normalizedTimeline(json)
        skeletonTimelineJSON = normalized
        artifacts.skeletonTimeline = normalized
        Logger.debug("📅 Skeleton timeline stored", category: .ai)

        await persistCheckpoint()
        recordObjectiveStatus(
            "skeleton_timeline",
            status: .completed,
            source: "system_persist",
            details: ["reason": "persisted"]
        )
    }

    private func storeArtifactRecord(_ artifact: JSON) async {
        guard artifact != .null else { return }

        guard let artifactId = artifact["id"].string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !artifactId.isEmpty else {
            Logger.warning("⚠️ Artifact record missing id; entry skipped.", category: .ai)
            return
        }

        let metadata = artifact["metadata"]
        let purpose = metadata["purpose"].string?.lowercased()
        let extractedContent = artifact["extracted_content"].stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldEnforceTimelineTools = (purpose == "resume_timeline") && !extractedContent.isEmpty
        artifacts.artifactRecords.removeAll { $0["id"].stringValue == artifactId }
        artifacts.artifactRecords.append(artifact)
        let sha = artifact["sha256"].stringValue
        Logger.debug("📦 Artifact record stored (id: \(artifactId), sha256: \(sha))", category: .ai)
        let message = DeveloperMessageTemplates.artifactStored(artifact: artifact)
        enqueueDeveloperStatus(from: message)

        if shouldEnforceTimelineTools {
            await orchestrator?.scheduleTimelineToolEnforcement()
        }
    }

    private func storeKnowledgeCard(_ card: JSON) async {
        guard card != .null else { return }

        // Inline public synchronous version logic to avoid overload ambiguity
        if let identifier = card["id"].string, !identifier.isEmpty {
            artifacts.knowledgeCards.removeAll { $0["id"].stringValue == identifier }
        }
        artifacts.knowledgeCards.append(card)
        Logger.debug("🃏 Knowledge card stored (id: \(card["id"].stringValue))", category: .ai)

        await persistCheckpoint()
    }

    func persistCheckpoint() async {
        let sections = artifacts.enabledSections
        await saveCheckpoint(
            applicantProfile: applicantProfileJSON,
            skeletonTimeline: skeletonTimelineJSON,
            enabledSections: sections.isEmpty ? nil : sections
        )
    }

    private func resetTransientState() {
        resetTranscript()
        toolRouter.reset()
        wizardTracker.reset()
        clearArtifacts()
        pendingExtraction = nil
        pendingPhaseAdvanceRequest = nil
        phaseAdvanceContinuationId = nil
        phaseAdvanceBlockCache = nil
        isProcessing = false
        isActive = false
        updateWaitingState(nil)
        clearLatestReasoningSummary()
        objectiveStatuses.removeAll()
        Task { await self.interviewState.resetLedger() }
    }

    private func buildAwaitingPayload(for request: OnboardingPhaseAdvanceRequest) -> JSON {
        var json = JSON()
        json["status"].string = "awaiting_user_approval"
        json["current_phase"].string = request.currentPhase.rawValue
        json["next_phase"].string = request.nextPhase.rawValue
        json["missing_objectives"] = JSON(request.missingObjectives)
        json["proposed_overrides"] = JSON(request.proposedOverrides)
        if let reason = request.reason, !reason.isEmpty {
            json["reason"].string = reason
        }
        return json
    }

    private struct PhaseAdvanceBlockCache {
        let missing: [String]
        let overrides: [String]
        let response: JSON

        func matches(missing: [String], overrides: [String]) -> Bool {
            missing.sorted() == self.missing.sorted() &&
            overrides.sorted() == self.overrides.sorted()
        }
    }

    private func refreshObjectiveStatuses() async {
        let session = await interviewState.currentSession()
        objectiveStatuses = session.objectiveLedger.reduce(into: [:]) { dict, entry in
            dict[entry.id] = entry.status
        }
    }
}
