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
    private var backend: LLMFacade.Backend = .openRouter

    private let uploadRegistry: OnboardingUploadRegistry
    private let artifactValidator = OnboardingArtifactValidator()
    @ObservationIgnored
    private lazy var toolExecutor: OnboardingToolExecutor = makeToolExecutor()
    private var processedToolIdentifiers: Set<String> = []

    private(set) var artifacts: OnboardingArtifacts
    private(set) var messages: [OnboardingMessage] = []
    private(set) var nextQuestions: [OnboardingQuestion] = []
    private(set) var currentPhase: OnboardingPhase = .resumeIntake
    private(set) var isProcessing = false
    private(set) var isActive = false
    private(set) var lastError: String?
    private(set) var allowWebSearch = false
    private(set) var allowWritingAnalysis = false
    private(set) var pendingExtraction: OnboardingPendingExtraction?
    private(set) var uploadedItems: [OnboardingUploadedItem] = []
    private(set) var schemaIssues: [String] = []

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
        refreshSchemaIssues()
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
        backend = .openRouter
        isActive = false
        isProcessing = false
        lastError = nil
        pendingExtraction = nil
        allowWritingAnalysis = false
        processedToolIdentifiers.removeAll()
        uploadRegistry.reset()
        uploadedItems = []
        refreshArtifacts()
        currentPhase = .resumeIntake
    }

    func setPhase(_ phase: OnboardingPhase) {
        guard currentPhase != phase else { return }
        currentPhase = phase

        guard let conversationId, let modelId else { return }

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
                conversationId: conversationId,
                modelId: modelId
            )
        }
    }

    func setWebSearchConsent(_ isAllowed: Bool) {
        allowWebSearch = isAllowed
        guard let conversationId, let modelId else { return }

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
                conversationId: conversationId,
                modelId: modelId
            )
        }
    }

    func setWritingAnalysisConsent(_ isAllowed: Bool) {
        allowWritingAnalysis = isAllowed
        let note = isAllowed
            ? "✍️ Writing-style analysis enabled. summarize_writing and persist_style_profile tools may run."
            : "🛑 Writing-style analysis disabled. Any pending summarize_writing or persist_style_profile calls will be rejected."
        messages.append(OnboardingMessage(role: .system, text: note))

        guard let conversationId, let modelId else { return }
        let payload = JSON([
            "type": "writing_analysis_consent",
            "allowed": isAllowed
        ])
        let messageText = payload.rawString(options: [.sortedKeys]) ?? payload.description
        Task { [weak self] in
            await self?.sendControlMessage(
                messageText,
                conversationId: conversationId,
                modelId: modelId
            )
        }
    }

    func startInterview(modelId: String, backend: LLMFacade.Backend = .openRouter) async {
        reset()
        self.modelId = modelId
        self.backend = backend
        guard llmFacade.hasBackend(backend) else {
            lastError = OnboardingError.backendUnsupported.errorDescription
            return
        }
        lastError = nil

        if backend == .openAI, let openAIConversationService {
            if let savedState = artifactStore.loadConversationState(), savedState.modelId == modelId {
                let resumeId = await openAIConversationService.registerPersistedConversation(savedState)
                conversationId = resumeId
                messages.append(OnboardingMessage(role: .system, text: "♻️ Resuming previous onboarding interview with saved OpenAI thread."))
                let resumePrompt = OnboardingPromptBuilder.resumeMessage(with: artifacts, phase: currentPhase)
                await sendControlMessage(resumePrompt, conversationId: resumeId, modelId: modelId)
                if lastError == nil {
                    isActive = true
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

            let (conversationId, response) = try await llmFacade.startConversation(
                systemPrompt: systemPrompt,
                userMessage: kickoff,
                modelId: modelId,
                backend: backend
            )
            self.conversationId = conversationId
            try await handleLLMResponse(response)
            isActive = true
            if backend == .openAI {
                await persistConversationStateIfNeeded()
            } else {
                artifactStore.clearConversationState()
            }
        } catch {
            lastError = error.localizedDescription
            Logger.error("OnboardingInterviewService.startInterview failed: \(error)")
        }

        isProcessing = false
    }

    func send(userMessage: String) async {
        guard let conversationId, let modelId else {
            lastError = "Interview has not been started"
            return
        }

        messages.append(OnboardingMessage(role: .user, text: userMessage))
        isProcessing = true
        lastError = nil

        do {
            let response = try await llmFacade.continueConversation(
                userMessage: userMessage,
                modelId: modelId,
                conversationId: conversationId,
                backend: backend
            )
            try await handleLLMResponse(response)
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
        guard pendingExtraction != nil, let conversationId, let modelId else { return }

        pendingExtraction = nil

        let payload = JSON([
            "type": "resume_extraction_confirmation",
            "raw_extraction": updatedExtraction,
            "notes": notes ?? ""
        ])

        messages.append(OnboardingMessage(role: .user, text: "Confirmed resume extraction."))
        isProcessing = true

        do {
            let response = try await llmFacade.continueConversation(
                userMessage: payload.rawString(options: [.sortedKeys]) ?? payload.description,
                modelId: modelId,
                conversationId: conversationId,
                backend: backend
            )
            try await handleLLMResponse(response)
        } catch {
            lastError = error.localizedDescription
            Logger.error("OnboardingInterviewService.confirmPendingExtraction failed: \(error)")
        }

        isProcessing = false
    }

    private func sendControlMessage(
        _ messageText: String,
        conversationId: UUID,
        modelId: String
    ) async {
        guard conversationId == self.conversationId, modelId == self.modelId else { return }
        isProcessing = true
        lastError = nil

        do {
            let response = try await llmFacade.continueConversation(
                userMessage: messageText,
                modelId: modelId,
                conversationId: conversationId,
                backend: backend
            )
            try await handleLLMResponse(response)
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
    func registerArtifact(data: Data, suggestedName: String) -> OnboardingUploadedItem {
        let item = uploadRegistry.registerArtifact(data: data, suggestedName: suggestedName)
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

    private func handleLLMResponse(_ responseText: String) async throws {
        let parsed = try OnboardingLLMResponseParser.parse(responseText)

        if !parsed.assistantReply.isEmpty {
            messages.append(OnboardingMessage(role: .assistant, text: parsed.assistantReply))
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

        await persistConversationStateIfNeeded()
    }

    private func processToolCalls(_ calls: [OnboardingToolCall]) async throws {
        guard let conversationId, let modelId else { return }

        var responses: [JSON] = []

        for call in calls where !processedToolIdentifiers.contains(call.identifier) {
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

        guard !responses.isEmpty else { return }

        let responseWrapper = JSON([
            "tool_responses": responses
        ])

        isProcessing = true
        do {
            let response = try await llmFacade.continueConversation(
                userMessage: responseWrapper.rawString(options: [.sortedKeys]) ?? responseWrapper.description,
                modelId: modelId,
                conversationId: conversationId,
                backend: backend
            )
            try await handleLLMResponse(response)
        } catch {
            lastError = error.localizedDescription
            Logger.error("OnboardingInterviewService.processToolCalls failed: \(error)")
        }
        isProcessing = false
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

    // MARK: - Delta Handling

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
