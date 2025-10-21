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
    private var processedToolIdentifiers: Set<String> = []

    private var defaultBackend: LLMFacade.Backend = .openAI
    private var defaultAllowWebSearch = true
    private var preferredModelId: String?

    private(set) var artifacts: OnboardingArtifacts
    private(set) var messages: [OnboardingMessage] = []
    private(set) var nextQuestions: [OnboardingQuestion] = []
    private(set) var currentPhase: OnboardingPhase = .resumeIntake
    private(set) var isProcessing = false
    private(set) var isActive = false
    private(set) var lastError: String?
    private(set) var allowWebSearch = true
    private(set) var allowWritingAnalysis = false
    private(set) var pendingExtraction: OnboardingPendingExtraction?
    private(set) var uploadedItems: [OnboardingUploadedItem] = []
    private(set) var schemaIssues: [String] = []
    private(set) var wizardStep: OnboardingWizardStep = .introduction
    private(set) var completedWizardSteps: Set<OnboardingWizardStep> = []
    private(set) var wizardStepStatuses: [OnboardingWizardStep: OnboardingWizardStepStatus] = [:]
    private(set) var pendingUploadRequests: [OnboardingUploadRequest] = []
    private(set) var pendingChoicePrompt: OnboardingChoicePrompt?
    private(set) var pendingApplicantProfileRequest: OnboardingApplicantProfileRequest?
    private(set) var pendingSectionToggleRequest: OnboardingSectionToggleRequest?
    private(set) var pendingSectionEntryRequests: [OnboardingSectionEntryRequest] = []
    private(set) var pendingContactsRequest: OnboardingContactsFetchRequest?

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
        recalculateWizardStatuses()
    }

    private func makeToolExecutor() -> OnboardingToolExecutor {
        OnboardingToolExecutor(
            artifactStore: artifactStore,
            applicantProfileStore: applicantProfileStore,
            experienceDefaultsStore: experienceDefaultsStore,
            coverRefStore: coverRefStore,
            uploadRegistry: uploadRegistry,
            artifactValidator: artifactValidator,
            allowWebSearch: { [weak self] in self?.allowWebSearch ?? false },
            allowWritingAnalysis: { [weak self] in self?.allowWritingAnalysis ?? false },
            refreshArtifacts: { [weak self] in self?.refreshArtifacts() },
            setPendingExtraction: { [weak self] extraction in self?.pendingExtraction = extraction }
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
        messages.removeAll()
        nextQuestions.removeAll()
        conversationId = nil
        modelId = nil
        backend = defaultBackend
        activeModelId = nil
        isActive = false
        isProcessing = false
        lastError = nil
        pendingExtraction = nil
        allowWritingAnalysis = false
        allowWebSearch = defaultAllowWebSearch
        processedToolIdentifiers.removeAll()
        uploadRegistry.reset()
        uploadedItems = []
        pendingUploadRequests.removeAll()
        pendingChoicePrompt = nil
        pendingApplicantProfileRequest = nil
        pendingSectionToggleRequest = nil
        pendingSectionEntryRequests.removeAll()
        pendingContactsRequest = nil
        completedWizardSteps.removeAll()
        wizardStep = .introduction
        refreshArtifacts()
        currentPhase = .resumeIntake
        recalculateWizardStatuses()
    }

    func setPhase(_ phase: OnboardingPhase) {
        guard currentPhase != phase else { return }
        currentPhase = phase
        syncWizardStepWithCurrentPhase(force: true)

        guard let conversationId else { return }

        let directive = OnboardingPromptBuilder.phaseDirective(for: phase)
        let directiveText = directive.rawString(options: [.sortedKeys]) ?? directive.description

        let headline = "🔄 Entering \(phase.displayName): \(phase.focusSummary)"
        messages.append(OnboardingMessage(role: .system, text: headline))

        if !phase.interviewPrompts.isEmpty {
            let promptList = phase.interviewPrompts.enumerated().map { index, item in
                "\(index + 1). \(item)"
            }.joined(separator: "\n")
            messages.append(OnboardingMessage(role: .system, text: "Phase prompts:\n\(promptList)"))
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

        let payload = JSON([
            "type": "web_search_consent",
            "allowed": isAllowed
        ])
        let note = isAllowed ? "✅ Web search enabled for this interview." : "🚫 Web search disabled for this interview."
        messages.append(OnboardingMessage(role: .system, text: note))

        let messageText = payload.rawString(options: [.sortedKeys]) ?? payload.description
        Task { [weak self] in
            await self?.sendControlMessage(
                messageText,
                conversationId: conversationId
            )
        }
    }

    func setWritingAnalysisConsent(_ isAllowed: Bool) {
        allowWritingAnalysis = isAllowed
        guard let conversationId else { return }
        let payload = JSON([
            "type": "writing_analysis_consent",
            "allowed": isAllowed
        ])
        let messageText = payload.rawString(options: [.sortedKeys]) ?? payload.description
        Task { [weak self] in
            await self?.sendControlMessage(
                messageText,
                conversationId: conversationId
            )
        }
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
        completedWizardSteps.insert(.introduction)
        transitionWizard(to: .resumeIntake)

        if resolvedBackend == .openAI, let openAIConversationService {
            if let savedState = artifactStore.loadConversationState(), savedState.modelId == modelId {
                let resumeId = await openAIConversationService.registerPersistedConversation(savedState)
                conversationId = resumeId
                messages.append(OnboardingMessage(role: .system, text: "♻️ Resuming previous onboarding interview with saved OpenAI thread."))
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

        messages.append(OnboardingMessage(role: .user, text: userMessage))
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
        pendingExtraction = nil
    }

    func confirmPendingExtraction(updatedExtraction: JSON, notes: String?) async {
        guard pendingExtraction != nil, let conversationId else { return }

        pendingExtraction = nil
        if wizardStep == .resumeIntake {
            completedWizardSteps.insert(.resumeIntake)
            recalculateWizardStatuses()
        }

        let payload = JSON([
            "type": "resume_extraction_confirmation",
            "raw_extraction": updatedExtraction,
            "notes": notes ?? ""
        ])

        messages.append(OnboardingMessage(role: .user, text: "Confirmed resume extraction."))
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
        let item = try uploadRegistry.registerResume(from: fileURL)
        refreshUploadedItems()
        appendSystemMessage("Uploaded resume ‘\(item.name)’. Tool: parse_resume with fileId \(item.id)")
        return item
    }

    @discardableResult
    func registerLinkedInProfile(url: URL) -> OnboardingUploadedItem {
        let item = uploadRegistry.registerLinkedInProfile(url: url)
        refreshUploadedItems()
        appendSystemMessage("LinkedIn URL registered. Tool: parse_linkedin with url \(url.absoluteString)")
        return item
    }

    @discardableResult
    func registerArtifact(
        data: Data,
        suggestedName: String,
        kind: OnboardingUploadedItem.Kind = .artifact
    ) -> OnboardingUploadedItem {
        let item = uploadRegistry.registerArtifact(data: data, suggestedName: suggestedName, kind: kind)
        refreshUploadedItems()
        appendSystemMessage("Artifact ‘\(item.name)’ available. Tool: summarize_artifact with fileId \(item.id)")
        return item
    }

    @discardableResult
    func registerWritingSample(data: Data, suggestedName: String) -> OnboardingUploadedItem {
        let item = uploadRegistry.registerWritingSample(data: data, suggestedName: suggestedName)
        refreshUploadedItems()
        appendSystemMessage("Writing sample ‘\(item.name)’ ready. Tool: summarize_writing or persist_style_profile will reference fileId \(item.id)")
        return item
    }

    private func refreshUploadedItems() {
        uploadedItems = uploadRegistry.items
    }

    // MARK: - Response Handling

    private func handleLLMResponse(
        _ responseText: String,
        updatingMessageId messageId: UUID? = nil
    ) async throws {
        let parsed = try OnboardingLLMResponseParser.parse(responseText)

        if !parsed.assistantReply.isEmpty {
            if let messageId = messageId {
                appendOrUpdateAssistantMessage(id: messageId, text: parsed.assistantReply)
            } else {
                messages.append(OnboardingMessage(role: .assistant, text: parsed.assistantReply))
            }
        } else if let messageId = messageId {
            removeMessage(withId: messageId)
        }

        if !parsed.deltaUpdates.isEmpty {
            try await toolExecutor.applyDeltaUpdates(parsed.deltaUpdates)
        }

        if !parsed.knowledgeCards.isEmpty {
            _ = artifactStore.appendKnowledgeCards(parsed.knowledgeCards)
        }

        if !parsed.factLedgerEntries.isEmpty {
            _ = artifactStore.appendFactLedgerEntries(parsed.factLedgerEntries)
        }

        if let skillMap = parsed.skillMapDelta {
            _ = artifactStore.mergeSkillMap(patch: skillMap)
        }

        if let styleProfile = parsed.styleProfile {
            artifactStore.saveStyleProfile(styleProfile)
        }

        if !parsed.writingSamples.isEmpty {
            toolExecutor.saveWritingSamples(parsed.writingSamples)
        }

        if let profileContext = parsed.profileContext?.trimmingCharacters(in: .whitespacesAndNewlines), !profileContext.isEmpty {
            artifactStore.updateProfileContext(profileContext)
        }

        if !parsed.needsVerification.isEmpty {
            _ = artifactStore.appendNeedsVerification(parsed.needsVerification)
        }

        refreshArtifacts()
        nextQuestions = parsed.nextQuestions

        if !parsed.toolCalls.isEmpty {
            try await processToolCalls(parsed.toolCalls)
        }

        syncWizardStepWithCurrentPhase()
        await persistConversationStateIfNeeded()
    }

    private func streamAssistantResponse(from handle: LLMStreamingHandle) async throws -> (String, UUID) {
        let mainMessageId = appendAssistantPlaceholder()
        var accumulatedText = ""

        var reasoningState: (id: UUID, text: String)?
        struct ToolStreamState {
            var messageId: UUID
            var inputBuffer: String
            var status: String
            var isComplete: Bool
        }
        var toolStates: [String: ToolStreamState] = [:]

        func formatToolPayload(_ text: String) -> String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "" }
            let maxLength = 600
            if trimmed.count <= maxLength {
                return trimmed
            }
            let index = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
            return String(trimmed[..<index]) + "…"
        }

        func updateReasoningMessage(with delta: String) {
            let trimmed = delta.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            var text = reasoningState?.text ?? ""
            text += (text.isEmpty ? "" : " ") + trimmed
            let messageId = reasoningState?.id ?? appendAssistantMessage("🧠 \(text)")

            appendOrUpdateAssistantMessage(id: messageId, text: "🧠 \(text)")
            reasoningState = (messageId, text)
        }

        func finalizeReasoningIfNeeded() {
            guard let state = reasoningState else { return }
            if !state.text.isEmpty {
                let display = "🧠 \(state.text)\n✅ Reasoning complete."
                appendOrUpdateAssistantMessage(id: state.id, text: display)
            }
        }

        func updateToolMessage(for event: LLMToolStreamEvent) {
            var state = toolStates[event.callId]
            if state == nil {
                let initialStatus = event.status ?? "Tool call started."
                let messageId = appendAssistantMessage("🔧 \(initialStatus)")
                state = ToolStreamState(
                    messageId: messageId,
                    inputBuffer: "",
                    status: initialStatus,
                    isComplete: false
                )
            }

            if let payload = event.payload {
                if event.appendsPayload {
                    state?.inputBuffer += payload
                } else {
                    state?.inputBuffer = payload
                }
            }

            if let status = event.status {
                state?.status = status
            }

            if event.isComplete {
                state?.isComplete = true
            }

            if let state {
                var display = "🔧 Tool \(event.callId)"
                display += "\n\(state.status)"
                if !state.inputBuffer.isEmpty {
                    let preview = formatToolPayload(state.inputBuffer)
                    if !preview.isEmpty {
                        display += "\n" + preview
                    }
                }
                if state.isComplete {
                    display += "\n✅ Tool complete."
                }
                appendOrUpdateAssistantMessage(id: state.messageId, text: display)
                toolStates[event.callId] = state
            }
        }

        func finalizeToolMessages() {
            for (id, state) in toolStates {
                if state.isComplete {
                    continue
                }
                var updated = state
                updated.isComplete = true
                var display = "🔧 Tool \(id)"
                display += "\n\(state.status)"
                if !state.inputBuffer.isEmpty {
                    let preview = formatToolPayload(state.inputBuffer)
                    if !preview.isEmpty {
                        display += "\n" + preview
                    }
                }
                display += "\n✅ Tool complete."
                appendOrUpdateAssistantMessage(id: state.messageId, text: display)
                toolStates[id] = updated
            }
        }

        do {
            for try await chunk in handle.stream {
                if let event = chunk.event {
                    switch event {
                    case .tool(let toolEvent):
                        updateToolMessage(for: toolEvent)
                    case .status(let message, let isComplete):
                        let statusId = appendAssistantMessage("ℹ️ \(message)")
                        if isComplete {
                            appendOrUpdateAssistantMessage(id: statusId, text: "ℹ️ \(message)\n✅ Complete.")
                        }
                    }
                }

                if let reasoning = chunk.reasoning {
                    updateReasoningMessage(with: reasoning)
                }

                if let content = chunk.content, !content.isEmpty {
                    accumulatedText += content
                    appendOrUpdateAssistantMessage(id: mainMessageId, text: accumulatedText)
                }

                if chunk.isFinished {
                    finalizeReasoningIfNeeded()
                    finalizeToolMessages()
                }
            }
        } catch {
            removeMessage(withId: mainMessageId)
            if let state = reasoningState {
                removeMessage(withId: state.id)
            }
            for state in toolStates.values {
                removeMessage(withId: state.messageId)
            }
            throw error
        }

        return (accumulatedText, mainMessageId)
    }

    private func processToolCalls(_ calls: [OnboardingToolCall]) async throws {
        guard conversationId != nil, modelId != nil else { return }

        var responses: [JSON] = []

        for call in calls where !processedToolIdentifiers.contains(call.identifier) {
            if handleCustomToolCall(call, responses: &responses) {
                processedToolIdentifiers.insert(call.identifier)
                continue
            }
            let result = try await toolExecutor.execute(call)
            processedToolIdentifiers.insert(call.identifier)
            let payload: [String: Any] = [
                "tool": call.tool,
                "id": call.identifier,
                "status": "ok",
                "result": result
            ]
            responses.append(JSON(payload))
        }

        await sendToolResponses(responses)
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
        messages.append(OnboardingMessage(role: .system, text: text))
    }

    @discardableResult
    private func appendAssistantMessage(_ text: String) -> UUID {
        let message = OnboardingMessage(role: .assistant, text: text)
        messages.append(message)
        return message.id
    }

    private func appendOrUpdateAssistantMessage(id: UUID, text: String) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            let existing = messages[index]
            messages[index] = OnboardingMessage(
                id: existing.id,
                role: existing.role,
                text: text,
                timestamp: existing.timestamp
            )
        }
    }

    @discardableResult
    private func appendAssistantPlaceholder() -> UUID {
        let placeholder = OnboardingMessage(role: .assistant, text: "")
        messages.append(placeholder)
        return placeholder.id
    }

    private func removeMessage(withId id: UUID) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages.remove(at: index)
        }
    }

    // MARK: - Wizard State & Requests

    private func transitionWizard(to step: OnboardingWizardStep) {
        wizardStep = step
        for prior in OnboardingWizardStep.allCases where prior.rawValue < step.rawValue {
            completedWizardSteps.insert(prior)
        }
        recalculateWizardStatuses()
    }

    private func syncWizardStepWithCurrentPhase(force: Bool = false) {
        guard isActive || force else { return }
        transitionWizard(to: wizardStepForPhase(currentPhase))
    }

    private func wizardStepForPhase(_ phase: OnboardingPhase) -> OnboardingWizardStep {
        switch phase {
        case .resumeIntake:
            return .resumeIntake
        case .artifactDiscovery:
            return .artifactDiscovery
        case .writingCorpus:
            return .writingCorpus
        case .wrapUp:
            return .wrapUp
        }
    }

    private func recalculateWizardStatuses() {
        var statuses: [OnboardingWizardStep: OnboardingWizardStepStatus] = [:]
        for step in OnboardingWizardStep.allCases {
            if step == wizardStep {
                statuses[step] = .current
            } else if completedWizardSteps.contains(step) {
                statuses[step] = .completed
            } else {
                statuses[step] = .pending
            }
        }
        wizardStepStatuses = statuses
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
        guard let index = pendingUploadRequests.firstIndex(where: { $0.id == id }) else { return }
        let request = pendingUploadRequests.remove(at: index)
        recalculateWizardStatuses()

        let result = JSON([
            "tool": "prompt_user_for_upload",
            "id": request.toolCallId,
            "status": "user_uploaded",
            "result": [
                "file_id": item.id,
                "filename": item.name,
                "kind": item.kind.rawValue
            ]
        ])

        await sendToolResponses([result])
    }

    func declineUploadRequest(id: UUID, reason: String? = nil) async {
        guard let index = pendingUploadRequests.firstIndex(where: { $0.id == id }) else { return }
        let request = pendingUploadRequests.remove(at: index)
        recalculateWizardStatuses()

        var payload: [String: Any] = [
            "tool": "prompt_user_for_upload",
            "id": request.toolCallId,
            "status": "declined"
        ]
        if let reason {
            payload["message"] = reason
        }

        await sendToolResponses([JSON(payload)])
    }

    func fulfillUploadRequest(id: UUID, fileURL: URL) async {
        guard let request = pendingUploadRequests.first(where: { $0.id == id }) else { return }

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
        guard let prompt = pendingChoicePrompt else { return }
        pendingChoicePrompt = nil

        let result = JSON([
            "tool": "ask_user_options",
            "id": prompt.toolCallId,
            "status": "ok",
            "selection": JSON(selectionIds)
        ])

        await sendToolResponses([result])
    }

    func cancelChoicePrompt(reason: String? = nil) async {
        guard let prompt = pendingChoicePrompt else { return }
        pendingChoicePrompt = nil
        var payload: [String: Any] = [
            "tool": "ask_user_options",
            "id": prompt.toolCallId,
            "status": "cancelled"
        ]
        if let reason {
            payload["message"] = reason
        }
        await sendToolResponses([JSON(payload)])
    }

    // MARK: - Applicant Profile Validation

    func approveApplicantProfileDraft(_ draft: ApplicantProfileDraft) async {
        let profile = applicantProfileStore.currentProfile()
        draft.apply(to: profile)
        applicantProfileStore.save(profile)
        let json = draft.toJSON()
        _ = artifactStore.mergeApplicantProfile(patch: json)
        refreshArtifacts()
        await broadcastResumeSnapshot(reason: "applicant_profile_validated")
        await completeApplicantProfileValidation(approvedProfile: json)
    }

    func completeApplicantProfileValidation(approvedProfile: JSON) async {
        guard let request = pendingApplicantProfileRequest else { return }
        pendingApplicantProfileRequest = nil

        let payload = JSON([
            "tool": "validate_applicant_profile",
            "id": request.toolCallId,
            "status": "ok",
            "profile": approvedProfile
        ])
        await sendToolResponses([payload])
    }

    func declineApplicantProfileValidation(reason: String? = nil) async {
        guard let request = pendingApplicantProfileRequest else { return }
        pendingApplicantProfileRequest = nil

        var payload: [String: Any] = [
            "tool": "validate_applicant_profile",
            "id": request.toolCallId,
            "status": "cancelled"
        ]
        if let reason {
            payload["message"] = reason
        }
        await sendToolResponses([JSON(payload)])
    }

    // MARK: - Resume Section Enablement

    func completeSectionToggleSelection(enabledSections: [String]) async {
        guard let request = pendingSectionToggleRequest else { return }
        pendingSectionToggleRequest = nil

        let keys = Set(
            enabledSections.compactMap { ExperienceSectionKey.fromOnboardingIdentifier($0) }
        )

        var draft = experienceDefaultsStore.loadDraft()
        draft.setEnabledSections(keys)
        experienceDefaultsStore.save(draft: draft)
        updateDefaultValuesArtifact(from: draft)
        await broadcastResumeSnapshot(reason: "resume_sections_enabled")

        let payload = JSON([
            "tool": "validate_enabled_resume_sections",
            "id": request.toolCallId,
            "status": "ok",
            "enabled_sections": JSON(enabledSections)
        ])
        await sendToolResponses([payload])
    }

    func cancelSectionToggleSelection(reason: String? = nil) async {
        guard let request = pendingSectionToggleRequest else { return }
        pendingSectionToggleRequest = nil

        var payload: [String: Any] = [
            "tool": "validate_enabled_resume_sections",
            "id": request.toolCallId,
            "status": "cancelled"
        ]
        if let reason {
            payload["message"] = reason
        }
        await sendToolResponses([JSON(payload)])
    }

    // MARK: - Section Entry Validation

    func completeSectionEntryRequest(id: UUID, approvedEntries: [JSON]) async {
        guard let index = pendingSectionEntryRequests.firstIndex(where: { $0.id == id }) else { return }
        let request = pendingSectionEntryRequests.remove(at: index)

        if let sectionKey = ExperienceSectionKey.fromOnboardingIdentifier(request.section) {
            do {
                try await applySectionEntries(sectionKey: sectionKey, entries: approvedEntries)
            } catch {
                lastError = error.localizedDescription
                Logger.error("OnboardingInterviewService.completeSectionEntryRequest failed: \(error)")
            }
        } else {
            Logger.warning("OnboardingInterviewService: Unknown section \(request.section)")
        }

        let payload = JSON([
            "tool": "validate_section_entries",
            "id": request.toolCallId,
            "status": "ok",
            "validated_entries": JSON(approvedEntries)
        ])
        await sendToolResponses([payload])
    }

    func declineSectionEntryRequest(id: UUID, reason: String? = nil) async {
        guard let index = pendingSectionEntryRequests.firstIndex(where: { $0.id == id }) else { return }
        let request = pendingSectionEntryRequests.remove(at: index)

        var payload: [String: Any] = [
            "tool": "validate_section_entries",
            "id": request.toolCallId,
            "status": "cancelled"
        ]
        if let reason {
            payload["message"] = reason
        }
        await sendToolResponses([JSON(payload)])
    }

    // MARK: - Contacts Fetch Handling

    func completeContactsFetch(profile: JSON) async {
        guard let request = pendingContactsRequest else { return }
        pendingContactsRequest = nil

        let payload = JSON([
            "tool": "fetch_from_system_contacts",
            "id": request.toolCallId,
            "status": "ok",
            "profile": profile
        ])
        await sendToolResponses([payload])
    }

    func declineContactsFetch(reason: String? = nil) async {
        guard let request = pendingContactsRequest else { return }
        pendingContactsRequest = nil

        var payload: [String: Any] = [
            "tool": "fetch_from_system_contacts",
            "id": request.toolCallId,
            "status": "cancelled"
        ]
        if let reason {
            payload["message"] = reason
        }
        await sendToolResponses([JSON(payload)])
    }

    func fetchApplicantProfileFromContacts() async {
        guard let request = pendingContactsRequest else { return }
        do {
            let profileJSON = try await SystemContactsFetcher.fetchApplicantProfile(requestedFields: request.requestedFields)
            await completeContactsFetch(profile: profileJSON)
        } catch {
            await declineContactsFetch(reason: error.localizedDescription)
        }
    }

    private func handleCustomToolCall(_ call: OnboardingToolCall, responses: inout [JSON]) -> Bool {
        switch call.tool {
        case "prompt_user_for_upload":
            if pendingUploadRequests.contains(where: { $0.toolCallId == call.identifier }) {
                return true
            }
            let request = OnboardingUploadRequest.fromToolCall(call)
            pendingUploadRequests.append(request)
            recalculateWizardStatuses()
            appendSystemMessage("📁 \(request.metadata.title): \(request.metadata.instructions)")
            let acknowledgement = JSON([
                "tool": call.tool,
                "id": call.identifier,
                "status": "awaiting_user"
            ])
            responses.append(acknowledgement)
            return true
        case "ask_user_options":
            pendingChoicePrompt = OnboardingChoicePrompt.fromToolCall(call)
            let acknowledgement = JSON([
                "tool": call.tool,
                "id": call.identifier,
                "status": "awaiting_user"
            ])
            responses.append(acknowledgement)
            return true
        case "validate_applicant_profile":
            pendingApplicantProfileRequest = OnboardingApplicantProfileRequest.fromToolCall(call)
            let acknowledgement = JSON([
                "tool": call.tool,
                "id": call.identifier,
                "status": "awaiting_user"
            ])
            responses.append(acknowledgement)
            return true
        case "validate_enabled_resume_sections":
            pendingSectionToggleRequest = OnboardingSectionToggleRequest.fromToolCall(call)
            let acknowledgement = JSON([
                "tool": call.tool,
                "id": call.identifier,
                "status": "awaiting_user"
            ])
            responses.append(acknowledgement)
            return true
        case "validate_section_entries":
            let request = OnboardingSectionEntryRequest.fromToolCall(call)
            if !pendingSectionEntryRequests.contains(where: { $0.toolCallId == call.identifier }) {
                pendingSectionEntryRequests.append(request)
            }
            let acknowledgement = JSON([
                "tool": call.tool,
                "id": call.identifier,
                "status": "awaiting_user"
            ])
            responses.append(acknowledgement)
            return true
        case "fetch_from_system_contacts":
            pendingContactsRequest = OnboardingContactsFetchRequest.fromToolCall(call)
            let acknowledgement = JSON([
                "tool": call.tool,
                "id": call.identifier,
                "status": "awaiting_user"
            ])
            responses.append(acknowledgement)
            return true
        default:
            return false
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

    private func applySectionEntries(sectionKey: ExperienceSectionKey, entries: [JSON]) async throws {
        guard let codec = ExperienceSectionCodecs.all.first(where: { $0.key == sectionKey }) else {
            throw OnboardingError.invalidArguments("Unsupported section \(sectionKey.rawValue)")
        }

        var decodedDraft = ExperienceDefaultsDraft()
        let jsonArray = JSON(entries)
        codec.decodeSection(from: jsonArray, into: &decodedDraft)

        var draft = experienceDefaultsStore.loadDraft()
        draft.replaceSection(sectionKey, with: decodedDraft)
        experienceDefaultsStore.save(draft: draft)
        updateDefaultValuesArtifact(from: draft)
        await broadcastResumeSnapshot(reason: "resume_section_updated_\(sectionKey.rawValue)")
    }


    private func resolvedModelIdentifier() -> String? {
        if let activeModelId { return activeModelId }
        if let modelId {
            return backend == .openAI ? modelId.replacingOccurrences(of: "openai/", with: "") : modelId
        }
        return nil
    }

    private func updateDefaultValuesArtifact(from draft: ExperienceDefaultsDraft) {
        let seed = ExperienceDefaultsEncoder.makeSeedDictionary(from: draft)
        let json = JSON(seed)
        _ = artifactStore.mergeDefaultValues(patch: json)
        refreshArtifacts()
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
