import Foundation
import Observation
import SwiftyJSON

@MainActor
@Observable
final class OnboardingInterviewService {
    private let llmFacade: LLMFacade
    private let artifactStore: OnboardingArtifactStore
    private let applicantProfileStore: ApplicantProfileStore
    private let experienceDefaultsStore: ExperienceDefaultsStore
    private let coverRefStore: CoverRefStore?
    private let openAIConversationService: OpenAIResponsesConversationService?

    private var conversationId: UUID?
    private var modelId: String?
    private var activeModelId: String?
    private var backend: LLMFacade.Backend = .openRouter

    private let uploadRegistry: OnboardingUploadRegistry
    private let artifactValidator = OnboardingArtifactValidator()
    @ObservationIgnored
    private lazy var toolExecutor: OnboardingToolExecutor = makeToolExecutor()
    @ObservationIgnored
    private lazy var toolPipeline: OnboardingInterviewToolPipeline = makeToolPipeline()
    @ObservationIgnored
    private lazy var consentManager: OnboardingInterviewConsentManager = makeConsentManager()
    @ObservationIgnored
    private lazy var uploadManager: OnboardingInterviewUploadManager = {
        OnboardingInterviewUploadManager(
            uploadRegistry: uploadRegistry,
            onItemsUpdated: { [weak self] items in self?.uploadedItems = items },
            onMessage: { [weak self] message in self?.appendSystemMessage(message) }
        )
    }()

    private var defaultBackend: LLMFacade.Backend = .openAI
    private var defaultAllowWebSearch = true
    private var preferredModelId: String?

    // Extracted managers
    private let messageManager = OnboardingInterviewMessageManager()
    private let requestManager = OnboardingInterviewRequestManager()
    private let wizardManager = OnboardingInterviewWizardManager()
    @ObservationIgnored
    private lazy var streamHandler: OnboardingInterviewStreamHandler = makeStreamHandler()
    @ObservationIgnored
    private lazy var requestHandler: OnboardingInterviewRequestHandler = makeRequestHandler()
    @ObservationIgnored
    private lazy var responseProcessor: OnboardingInterviewResponseProcessor = makeResponseProcessor()

    private(set) var artifacts: OnboardingArtifacts
    private(set) var currentPhase: OnboardingPhase = .resumeIntake
    private(set) var isProcessing = false
    private(set) var isActive = false
    private(set) var lastError: String?
    private(set) var allowWebSearch = true
    private(set) var allowWritingAnalysis = false
    private(set) var uploadedItems: [OnboardingUploadedItem] = []
    private(set) var schemaIssues: [String] = []

    // Delegate to managers for these properties
    var messages: [OnboardingMessage] { messageManager.messages }
    var nextQuestions: [OnboardingQuestion] { messageManager.nextQuestions }
    var wizardStep: OnboardingWizardStep { wizardManager.wizardStep }
    var completedWizardSteps: Set<OnboardingWizardStep> { wizardManager.completedWizardSteps }
    var wizardStepStatuses: [OnboardingWizardStep: OnboardingWizardStepStatus] { wizardManager.wizardStepStatuses }
    var pendingUploadRequests: [OnboardingUploadRequest] { requestManager.pendingUploadRequests }
    var pendingChoicePrompt: OnboardingChoicePrompt? { requestManager.pendingChoicePrompt }
    var pendingApplicantProfileRequest: OnboardingApplicantProfileRequest? { requestManager.pendingApplicantProfileRequest }
    var pendingSectionToggleRequest: OnboardingSectionToggleRequest? { requestManager.pendingSectionToggleRequest }
    var pendingSectionEntryRequests: [OnboardingSectionEntryRequest] { requestManager.pendingSectionEntryRequests }
    var pendingContactsRequest: OnboardingContactsFetchRequest? { requestManager.pendingContactsRequest }
    var pendingExtraction: OnboardingPendingExtraction? { requestManager.pendingExtraction }

    var preferredBackend: LLMFacade.Backend {
        defaultBackend
    }

    var preferredModelIdForDisplay: String? {
        preferredModelId
    }

    init(
        llmFacade: LLMFacade,
        artifactStore: OnboardingArtifactStore,
        applicantProfileStore: ApplicantProfileStore,
        experienceDefaultsStore: ExperienceDefaultsStore,
        coverRefStore: CoverRefStore? = nil,
        openAIConversationService: OpenAIResponsesConversationService? = nil,
        uploadRegistry: OnboardingUploadRegistry? = nil
    ) {
        self.llmFacade = llmFacade
        self.artifactStore = artifactStore
        self.applicantProfileStore = applicantProfileStore
        self.experienceDefaultsStore = experienceDefaultsStore
        self.coverRefStore = coverRefStore
        self.openAIConversationService = openAIConversationService
        self.uploadRegistry = uploadRegistry ?? OnboardingUploadRegistry()
        self.artifacts = artifactStore.loadArtifacts()
        self.allowWebSearch = defaultAllowWebSearch
        refreshSchemaIssues()
        wizardManager.currentSnapshot()
        _ = uploadManager
    }

    private func makeStreamHandler() -> OnboardingInterviewStreamHandler {
        OnboardingInterviewStreamHandler(messageManager: messageManager)
    }

    private func makeRequestHandler() -> OnboardingInterviewRequestHandler {
        OnboardingInterviewRequestHandler(
            requestManager: requestManager,
            wizardManager: wizardManager,
            artifactStore: artifactStore,
            applicantProfileStore: applicantProfileStore,
            experienceDefaultsStore: experienceDefaultsStore,
            sendToolResponses: { [weak self] responses in
                await self?.sendToolResponses(responses)
            },
            broadcastResumeSnapshot: { [weak self] reason in
                await self?.broadcastResumeSnapshot(reason: reason)
            }
        )
    }

    private func makeResponseProcessor() -> OnboardingInterviewResponseProcessor {
        OnboardingInterviewResponseProcessor(
            messageManager: messageManager,
            artifactStore: artifactStore,
            toolExecutor: toolExecutor,
            toolPipeline: toolPipeline,
            wizardManager: wizardManager,
            refreshArtifacts: { [weak self] in self?.refreshArtifacts() },
            syncWizardStep: { [weak self] in self?.syncWizardStepWithCurrentPhase() },
            persistConversationState: { [weak self] in await self?.persistConversationStateIfNeeded() }
        )
    }

    private func makeToolExecutor() -> OnboardingToolExecutor {
        OnboardingToolExecutor(
            artifactStore: artifactStore,
            applicantProfileStore: applicantProfileStore,
            experienceDefaultsStore: experienceDefaultsStore,
            coverRefStore: coverRefStore,
            uploadRegistry: uploadManager.registry,
            artifactValidator: artifactValidator,
            allowWebSearch: { [weak self] in self?.allowWebSearch ?? false },
            allowWritingAnalysis: { [weak self] in self?.allowWritingAnalysis ?? false },
            refreshArtifacts: { [weak self] in self?.refreshArtifacts() },
            setPendingExtraction: { [weak self] extraction in self?.requestManager.setPendingExtraction(extraction) }
        )
    }

    private func makeConsentManager() -> OnboardingInterviewConsentManager {
        OnboardingInterviewConsentManager(
            appendSystemMessage: { [weak self] message in
                self?.appendSystemMessage(message)
            },
            sendControlMessage: { [weak self] message, conversationId in
                await self?.sendControlMessage(message, conversationId: conversationId)
            }
        )
    }

    private func makeToolPipeline() -> OnboardingInterviewToolPipeline {
        OnboardingInterviewToolPipeline(
            toolExecutor: toolExecutor,
            customHandler: { [weak self] call in
                guard let self else { return .unhandled }
                return self.handleCustomToolCall(call)
            },
            sendResponses: { [weak self] responses in
                await self?.sendToolResponses(responses)
            }
        )
    }

    // MARK: - Backend Availability

    func availableBackends() -> [LLMFacade.Backend] {
        llmFacade
            .availableBackends()
            .filter { llmFacade.supportsConversations(for: $0) }
    }

    // MARK: - Session Lifecycle

    func reset() {
        messageManager.reset()
        requestManager.reset()
        wizardManager.reset()
        conversationId = nil
        modelId = nil
        backend = defaultBackend
        activeModelId = nil
        isActive = false
        isProcessing = false
        lastError = nil
        allowWritingAnalysis = false
        allowWebSearch = defaultAllowWebSearch
        uploadManager.reset()
        uploadedItems = []
        refreshArtifacts()
        currentPhase = .resumeIntake
        toolPipeline.reset()
    }

    func setPhase(_ phase: OnboardingPhase) {
        guard currentPhase != phase else { return }
        currentPhase = phase
        syncWizardStepWithCurrentPhase(force: true)

        guard let conversationId else { return }

        let directive = OnboardingPromptBuilder.phaseDirective(for: phase)
        let directiveText = directive.rawString(options: [.sortedKeys]) ?? directive.description

        let headline = "🔄 Entering \(phase.displayName): \(phase.focusSummary)"
        messageManager.appendSystemMessage(headline)

        if !phase.interviewPrompts.isEmpty {
            let promptList = phase.interviewPrompts.enumerated().map { index, item in
                "\(index + 1). \(item)"
            }.joined(separator: "\n")
            messageManager.appendSystemMessage("Phase prompts:\n\(promptList)")
        }

        Task { [weak self] in
            await self?.sendControlMessage(
                directiveText,
                conversationId: conversationId
            )
        }
    }

    func setWebSearchConsent(_ isAllowed: Bool) {
        allowWebSearch = isAllowed
        defaultAllowWebSearch = isAllowed
        guard let conversationId else { return }
        Task { await consentManager.handleWebSearchConsent(isAllowed: isAllowed, conversationId: conversationId) }
    }

    func setWritingAnalysisConsent(_ isAllowed: Bool) {
        allowWritingAnalysis = isAllowed
        guard let conversationId else { return }
        Task { await consentManager.handleWritingAnalysisConsent(isAllowed: isAllowed, conversationId: conversationId) }
    }

    func startInterview(modelId: String, backend: LLMFacade.Backend = .openRouter) async {
        preferredModelId = modelId
        reset()
        let desiredBackend = backend
        let resolvedBackend: LLMFacade.Backend
        if llmFacade.hasBackend(desiredBackend) {
            resolvedBackend = desiredBackend
        } else if llmFacade.hasBackend(defaultBackend) {
            resolvedBackend = defaultBackend
        } else if let fallback = llmFacade.availableBackends().first {
            resolvedBackend = fallback
        } else {
            lastError = OnboardingError.backendUnsupported.errorDescription
            return
        }

        self.modelId = modelId
        self.backend = resolvedBackend
        defaultBackend = resolvedBackend
        lastError = nil
        let normalizedModelId = resolvedBackend == .openAI ? modelId.replacingOccurrences(of: "openai/", with: "") : modelId
        activeModelId = normalizedModelId
        wizardManager.markCompleted(.introduction)
        wizardManager.transition(to: .resumeIntake)

        if resolvedBackend == .openAI, let openAIConversationService {
            if let savedState = artifactStore.loadConversationState(), savedState.modelId == modelId {
                let resumeId = await openAIConversationService.registerPersistedConversation(savedState)
                conversationId = resumeId
                messageManager.appendSystemMessage("♻️ Resuming previous onboarding interview with saved OpenAI thread.")
                let resumePrompt = OnboardingPromptBuilder.resumeMessage(with: artifacts, phase: currentPhase)
                await sendControlMessage(resumePrompt, conversationId: resumeId)
                if lastError == nil {
                    isActive = true
                    syncWizardStepWithCurrentPhase()
                    return
                } else {
                    Logger.warning("Resume attempt failed, starting fresh session instead.")
                    conversationId = nil
                    artifactStore.clearConversationState()
                }
            } else {
                artifactStore.clearConversationState()
            }
        }

        isProcessing = true

        do {
            let systemPrompt = OnboardingPromptBuilder.systemPrompt()
            let kickoff = OnboardingPromptBuilder.kickoffMessage(with: artifacts, phase: currentPhase)

            if resolvedBackend == .openAI {
                let handle = try await llmFacade.startConversationStreaming(
                    systemPrompt: systemPrompt,
                    userMessage: kickoff,
                    modelId: (activeModelId ?? normalizedModelId),
                    backend: resolvedBackend
                )
                guard let conversationId = handle.conversationId else {
                    throw LLMError.clientError("Failed to establish OpenAI conversation")
                }
                self.conversationId = conversationId
                let (responseText, messageId) = try await streamAssistantResponse(from: handle)
                try await handleLLMResponse(responseText, updatingMessageId: messageId)
                await persistConversationStateIfNeeded()
            } else {
                let (conversationId, response) = try await llmFacade.startConversation(
                    systemPrompt: systemPrompt,
                    userMessage: kickoff,
                    modelId: (activeModelId ?? normalizedModelId),
                    backend: resolvedBackend
                )
                self.conversationId = conversationId
                try await handleLLMResponse(response)
                artifactStore.clearConversationState()
            }
            isActive = true
            syncWizardStepWithCurrentPhase()
        } catch {
            lastError = error.localizedDescription
            Logger.error("OnboardingInterviewService.startInterview failed: \(error)")
        }

        isProcessing = false
    }

    func send(userMessage: String) async {
        guard let conversationId else {
            lastError = "Interview has not been started"
            return
        }
        guard let resolvedModelId = resolvedModelIdentifier() else {
            lastError = "Interview model is unavailable"
            return
        }

        messageManager.appendUserMessage(userMessage)
        isProcessing = true
        lastError = nil

        do {
            if backend == .openAI {
                let handle = try await llmFacade.continueConversationStreaming(
                    userMessage: userMessage,
                    modelId: resolvedModelId,
                    conversationId: conversationId,
                    backend: backend
                )
                let (responseText, messageId) = try await streamAssistantResponse(from: handle)
                try await handleLLMResponse(responseText, updatingMessageId: messageId)
                await persistConversationStateIfNeeded()
            } else {
                let response = try await llmFacade.continueConversation(
                    userMessage: userMessage,
                    modelId: resolvedModelId,
                    conversationId: conversationId,
                    backend: backend
                )
                try await handleLLMResponse(response)
            }
        } catch {
            lastError = error.localizedDescription
            Logger.error("OnboardingInterviewService.send failed: \(error)")
        }

        isProcessing = false
    }

    func cancelPendingExtraction() {
        _ = requestManager.clearPendingExtraction()
    }

    func confirmPendingExtraction(updatedExtraction: JSON, notes: String?) async {
        guard requestManager.pendingExtraction != nil, let conversationId else { return }

        _ = requestManager.clearPendingExtraction()
        if wizardStep == .resumeIntake {
            wizardManager.markCompleted(.resumeIntake)
        }

        let payload = JSON([
            "type": "resume_extraction_confirmation",
            "raw_extraction": updatedExtraction,
            "notes": notes ?? ""
        ])

        messageManager.appendUserMessage("Confirmed resume extraction.")
        isProcessing = true

        guard let resolvedModelId = resolvedModelIdentifier() else {
            lastError = "Interview model is unavailable"
            isProcessing = false
            return
        }

        do {
            let payloadText = payload.rawString(options: [.sortedKeys]) ?? payload.description
            if backend == .openAI {
                let handle = try await llmFacade.continueConversationStreaming(
                    userMessage: payloadText,
                    modelId: resolvedModelId,
                    conversationId: conversationId,
                    backend: backend
                )
                let (responseText, messageId) = try await streamAssistantResponse(from: handle)
                try await handleLLMResponse(responseText, updatingMessageId: messageId)
                await persistConversationStateIfNeeded()
            } else {
                let response = try await llmFacade.continueConversation(
                    userMessage: payloadText,
                    modelId: resolvedModelId,
                    conversationId: conversationId,
                    backend: backend
                )
                try await handleLLMResponse(response)
            }
        } catch {
            lastError = error.localizedDescription
            Logger.error("OnboardingInterviewService.confirmPendingExtraction failed: \(error)")
        }

        isProcessing = false
    }

    private func sendControlMessage(
        _ messageText: String,
        conversationId: UUID
    ) async {
        guard conversationId == self.conversationId else { return }
        isProcessing = true
        lastError = nil

        guard let resolvedModelId = resolvedModelIdentifier() else {
            lastError = "Interview model is unavailable"
            isProcessing = false
            return
        }

        do {
            if backend == .openAI {
                let handle = try await llmFacade.continueConversationStreaming(
                    userMessage: messageText,
                    modelId: resolvedModelId,
                    conversationId: conversationId,
                    backend: backend
                )
                let (responseText, messageId) = try await streamAssistantResponse(from: handle)
                try await handleLLMResponse(responseText, updatingMessageId: messageId)
                await persistConversationStateIfNeeded()
            } else {
                let response = try await llmFacade.continueConversation(
                    userMessage: messageText,
                    modelId: resolvedModelId,
                    conversationId: conversationId,
                    backend: backend
                )
                try await handleLLMResponse(response)
            }
        } catch {
            lastError = error.localizedDescription
            Logger.error("OnboardingInterviewService.sendControlMessage failed: \(error)")
        }

        isProcessing = false
    }

    private func persistConversationStateIfNeeded() async {
        guard backend == .openAI,
              let conversationId,
              let openAIConversationService else { return }
        if let state = await openAIConversationService.persistedState(for: conversationId) {
            artifactStore.saveConversationState(state)
        }
    }

    // MARK: - Upload Management

    @discardableResult
    func registerResume(fileURL: URL) throws -> OnboardingUploadedItem {
        return try uploadManager.registerResume(from: fileURL)
    }

    @discardableResult
    func registerLinkedInProfile(url: URL) -> OnboardingUploadedItem {
        return uploadManager.registerLinkedInProfile(url: url)
    }

    @discardableResult
    func registerArtifact(
        data: Data,
        suggestedName: String,
        kind: OnboardingUploadedItem.Kind = .artifact
    ) -> OnboardingUploadedItem {
        return uploadManager.registerArtifact(data: data, suggestedName: suggestedName, kind: kind)
    }

    @discardableResult
    func registerWritingSample(data: Data, suggestedName: String) -> OnboardingUploadedItem {
        return uploadManager.registerWritingSample(data: data, suggestedName: suggestedName)
    }

    // MARK: - Response Handling

    private func handleLLMResponse(
        _ responseText: String,
        updatingMessageId messageId: UUID? = nil
    ) async throws {
        try await responseProcessor.handleLLMResponse(responseText, updatingMessageId: messageId)
    }

    private func streamAssistantResponse(from handle: LLMStreamingHandle) async throws -> (String, UUID) {
        return try await streamHandler.streamAssistantResponse(from: handle)
    }

    // MARK: - Artifact Helpers

    private func refreshArtifacts() {
        artifacts = artifactStore.loadArtifacts()
        refreshSchemaIssues()
    }

    private func refreshSchemaIssues() {
        schemaIssues = artifactValidator.issues(for: artifacts)
    }

    private func appendSystemMessage(_ text: String) {
        messageManager.appendSystemMessage(text)
    }

    // MARK: - Wizard State & Requests

    private func transitionWizard(to step: OnboardingWizardStep) {
        wizardManager.transition(to: step)
    }

    private func syncWizardStepWithCurrentPhase(force: Bool = false) {
        guard isActive || force else { return }
        wizardManager.sync(with: currentPhase)
    }

    func setPreferredDefaults(modelId: String?, backend: LLMFacade.Backend, webSearchAllowed: Bool) {
        preferredModelId = modelId
        defaultBackend = backend
        defaultAllowWebSearch = webSearchAllowed
        if !isActive {
            allowWebSearch = webSearchAllowed
            self.backend = backend
        }
    }

    func completeUploadRequest(id: UUID, with item: OnboardingUploadedItem) async {
        await requestHandler.completeUploadRequest(id: id, with: item)
    }

    func declineUploadRequest(id: UUID, reason: String? = nil) async {
        await requestHandler.declineUploadRequest(id: id, reason: reason)
    }

    func fulfillUploadRequest(id: UUID, fileURL: URL) async {
        guard let request = requestManager.uploadRequest(id: id) else { return }

        do {
            let item: OnboardingUploadedItem
            switch request.kind {
            case .resume:
                item = try registerResume(fileURL: fileURL)
            case .writingSample:
                let data = try Data(contentsOf: fileURL)
                item = registerWritingSample(data: data, suggestedName: fileURL.lastPathComponent)
            case .artifact:
                let data = try Data(contentsOf: fileURL)
                item = registerArtifact(data: data, suggestedName: fileURL.lastPathComponent)
            case .generic:
                let data = try Data(contentsOf: fileURL)
                item = registerArtifact(
                    data: data,
                    suggestedName: fileURL.lastPathComponent,
                    kind: OnboardingUploadedItem.Kind.generic
                )
            case .linkedIn:
                let linkText = try String(contentsOf: fileURL, encoding: .utf8)
                guard let url = URL(string: linkText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    throw OnboardingError.invalidArguments("LinkedIn upload did not contain a valid URL")
                }
                item = registerLinkedInProfile(url: url)
            }
            await completeUploadRequest(id: id, with: item)
        } catch {
            lastError = error.localizedDescription
            Logger.error("OnboardingInterviewService.fulfillUploadRequest failed: \(error)")
        }
    }

    func fulfillUploadRequest(id: UUID, link: URL) async {
        let item = registerLinkedInProfile(url: link)
        await completeUploadRequest(id: id, with: item)
    }

    // MARK: - Choice Prompt Handling

    func resolveChoicePrompt(selectionIds: [String]) async {
        await requestHandler.resolveChoicePrompt(selectionIds: selectionIds)
    }

    func cancelChoicePrompt(reason: String? = nil) async {
        await requestHandler.cancelChoicePrompt(reason: reason)
    }

    // MARK: - Applicant Profile Validation

    func approveApplicantProfileDraft(_ draft: ApplicantProfileDraft) async {
        await requestHandler.approveApplicantProfileDraft(draft)
        refreshArtifacts()
    }

    func completeApplicantProfileValidation(approvedProfile: JSON) async {
        await requestHandler.completeApplicantProfileValidation(approvedProfile: approvedProfile)
    }

    func declineApplicantProfileValidation(reason: String? = nil) async {
        await requestHandler.declineApplicantProfileValidation(reason: reason)
    }

    // MARK: - Resume Section Enablement

    func completeSectionToggleSelection(enabledSections: [String]) async {
        await requestHandler.completeSectionToggleSelection(enabledSections: enabledSections)
        refreshArtifacts()
    }

    func cancelSectionToggleSelection(reason: String? = nil) async {
        await requestHandler.cancelSectionToggleSelection(reason: reason)
    }

    // MARK: - Section Entry Validation

    func completeSectionEntryRequest(id: UUID, approvedEntries: [JSON]) async {
        await requestHandler.completeSectionEntryRequest(id: id, approvedEntries: approvedEntries)
        refreshArtifacts()
    }

    func declineSectionEntryRequest(id: UUID, reason: String? = nil) async {
        await requestHandler.declineSectionEntryRequest(id: id, reason: reason)
    }

    // MARK: - Contacts Fetch Handling

    func completeContactsFetch(profile: JSON) async {
        await requestHandler.completeContactsFetch(profile: profile)
    }

    func declineContactsFetch(reason: String? = nil) async {
        await requestHandler.declineContactsFetch(reason: reason)
    }

    func fetchApplicantProfileFromContacts() async {
        await requestHandler.fetchApplicantProfileFromContacts()
    }

    private func handleCustomToolCall(_ call: OnboardingToolCall) -> OnboardingInterviewToolPipeline.CustomResult {
        switch call.tool {
        case "prompt_user_for_upload":
            if requestManager.pendingUploadRequests.contains(where: { $0.toolCallId == call.identifier }) {
                return .handled()
            }
            let request = OnboardingUploadRequest.fromToolCall(call)
            requestManager.addUploadRequest(request)
            wizardManager.currentSnapshot()
            appendSystemMessage("📁 \(request.metadata.title): \(request.metadata.instructions)")
            let acknowledgement = JSON([
                "tool": call.tool,
                "id": call.identifier,
                "status": "awaiting_user"
            ])
            return .handled([acknowledgement])
        case "ask_user_options":
            requestManager.setChoicePrompt(OnboardingChoicePrompt.fromToolCall(call))
            wizardManager.currentSnapshot()
            let acknowledgement = JSON([
                "tool": call.tool,
                "id": call.identifier,
                "status": "awaiting_user"
            ])
            return .handled([acknowledgement])
        case "validate_applicant_profile":
            requestManager.setApplicantProfileRequest(OnboardingApplicantProfileRequest.fromToolCall(call))
            wizardManager.currentSnapshot()
            let acknowledgement = JSON([
                "tool": call.tool,
                "id": call.identifier,
                "status": "awaiting_user"
            ])
            return .handled([acknowledgement])
        case "validate_enabled_resume_sections":
            requestManager.setSectionToggleRequest(OnboardingSectionToggleRequest.fromToolCall(call))
            wizardManager.currentSnapshot()
            let acknowledgement = JSON([
                "tool": call.tool,
                "id": call.identifier,
                "status": "awaiting_user"
            ])
            return .handled([acknowledgement])
        case "validate_section_entries":
            let request = OnboardingSectionEntryRequest.fromToolCall(call)
            requestManager.addSectionEntryRequest(request)
            wizardManager.currentSnapshot()
            let acknowledgement = JSON([
                "tool": call.tool,
                "id": call.identifier,
                "status": "awaiting_user"
            ])
            return .handled([acknowledgement])
        case "fetch_from_system_contacts":
            requestManager.setContactsRequest(OnboardingContactsFetchRequest.fromToolCall(call))
            wizardManager.currentSnapshot()
            let acknowledgement = JSON([
                "tool": call.tool,
                "id": call.identifier,
                "status": "awaiting_user"
            ])
            return .handled([acknowledgement])
        default:
            return .unhandled
        }
    }

    private func sendToolResponses(_ responses: [JSON]) async {
        guard let conversationId else { return }
        guard !responses.isEmpty else { return }

        let responseWrapper = JSON([
            "tool_responses": responses
        ])

        isProcessing = true

        guard let resolvedModelId = resolvedModelIdentifier() else {
            lastError = "Interview model is unavailable"
            isProcessing = false
            return
        }

        do {
            let payload = responseWrapper.rawString(options: [.sortedKeys]) ?? responseWrapper.description
            if backend == .openAI {
                let handle = try await llmFacade.continueConversationStreaming(
                    userMessage: payload,
                    modelId: resolvedModelId,
                    conversationId: conversationId,
                    backend: backend
                )
                let (responseText, messageId) = try await streamAssistantResponse(from: handle)
                try await handleLLMResponse(responseText, updatingMessageId: messageId)
                await persistConversationStateIfNeeded()
            } else {
                let response = try await llmFacade.continueConversation(
                    userMessage: payload,
                    modelId: resolvedModelId,
                    conversationId: conversationId,
                    backend: backend
                )
                try await handleLLMResponse(response)
            }
        } catch {
            lastError = error.localizedDescription
            Logger.error("OnboardingInterviewService.sendToolResponses failed: \(error)")
        }
        isProcessing = false
    }

    private func resolvedModelIdentifier() -> String? {
        if let activeModelId { return activeModelId }
        if let modelId {
            return backend == .openAI ? modelId.replacingOccurrences(of: "openai/", with: "") : modelId
        }
        return nil
    }

    private func broadcastResumeSnapshot(reason: String) async {
        guard let conversationId else { return }
        let latest = artifactStore.loadArtifacts()

        var payloadDict: [String: Any] = [
            "type": "resume_snapshot",
            "reason": reason
        ]
        if let profile = latest.applicantProfile?.dictionaryObject {
            payloadDict["applicant_profile"] = profile
        }
        if let defaults = latest.defaultValues?.dictionaryObject {
            payloadDict["default_values"] = defaults
        }

        let payload = JSON(payloadDict)
        let messageText = payload.rawString(options: [.sortedKeys]) ?? payload.description
        await sendControlMessage(messageText, conversationId: conversationId)
    }

    // MARK: - Errors

    enum OnboardingError: Error, LocalizedError {
        case backendUnsupported
        case invalidResponseFormat
        case unsupportedTool(String)
        case missingResource(String)
        case invalidArguments(String)
        case webSearchNotAllowed
        case writingAnalysisNotAllowed

        var errorDescription: String? {
            switch self {
            case .backendUnsupported:
                return "Selected backend is not configured for onboarding interviews"
            case .invalidResponseFormat:
                return "Assistant response was not valid JSON"
            case .unsupportedTool(let tool):
                return "Assistant requested unsupported tool \(tool)"
            case .missingResource(let resource):
                return "Required resource for \(resource) was not available"
            case .invalidArguments(let message):
                return message
            case .webSearchNotAllowed:
                return "Web lookup requested without user consent"
            case .writingAnalysisNotAllowed:
                return "Writing-style analysis requested without explicit user consent"
            }
        }
    }
}
