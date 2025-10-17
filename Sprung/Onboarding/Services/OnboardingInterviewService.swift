import Foundation
import Observation
import SwiftyJSON

@MainActor
@Observable
final class OnboardingInterviewService {
    struct UploadedItem: Identifiable, Equatable, Sendable {
        enum Kind: String, Sendable {
            case resume
            case linkedInProfile
            case artifact
        }

        let id: String
        let name: String
        let kind: Kind
        let data: Data?
        let url: URL?
        let createdAt: Date
    }

    struct PendingExtraction: @unchecked Sendable {
        var rawExtraction: JSON
        var uncertainties: [String]
    }

    private struct ToolCall: @unchecked Sendable {
        let identifier: String
        let tool: String
        let arguments: JSON
    }

    private let llmFacade: LLMFacade
    private let artifactStore: OnboardingArtifactStore
    private let applicantProfileStore: ApplicantProfileStore
    private let openAIConversationService: OpenAIResponsesConversationService?

    private var conversationId: UUID?
    private var modelId: String?
    private var backend: LLMFacade.Backend = .openRouter

    private var uploadsById: [String: UploadedItem] = [:]
    private var processedToolIdentifiers: Set<String> = []

    private(set) var artifacts: OnboardingArtifacts
    private(set) var messages: [OnboardingMessage] = []
    private(set) var nextQuestions: [OnboardingQuestion] = []
    private(set) var currentPhase: OnboardingPhase = .coreFacts
    private(set) var isProcessing = false
    private(set) var isActive = false
    private(set) var lastError: String?
    private(set) var allowWebSearch = false
    private(set) var pendingExtraction: PendingExtraction?
    private(set) var uploadedItems: [UploadedItem] = []
    private(set) var schemaIssues: [String] = []

    init(
        llmFacade: LLMFacade,
        artifactStore: OnboardingArtifactStore,
        applicantProfileStore: ApplicantProfileStore,
        openAIConversationService: OpenAIResponsesConversationService? = nil
    ) {
        self.llmFacade = llmFacade
        self.artifactStore = artifactStore
        self.applicantProfileStore = applicantProfileStore
        self.openAIConversationService = openAIConversationService
        self.artifacts = artifactStore.loadArtifacts()
        refreshSchemaIssues()
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
        processedToolIdentifiers.removeAll()
        refreshArtifacts()
        currentPhase = .coreFacts
    }

    func setPhase(_ phase: OnboardingPhase) {
        guard currentPhase != phase else { return }
        currentPhase = phase

        guard let conversationId, let modelId else { return }

        let directive = PromptBuilder.phaseDirective(for: phase)
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
                let resumePrompt = PromptBuilder.resumeMessage(with: artifacts, phase: currentPhase)
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
            let systemPrompt = PromptBuilder.systemPrompt()
            let kickoff = PromptBuilder.kickoffMessage(with: artifacts, phase: currentPhase)

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
    func registerResume(fileURL: URL) throws -> UploadedItem {
        let data = try Data(contentsOf: fileURL)
        let item = UploadedItem(
            id: UUID().uuidString,
            name: fileURL.lastPathComponent,
            kind: .resume,
            data: data,
            url: nil,
            createdAt: Date()
        )
        addUpload(item)
        appendSystemMessage("Uploaded resume ‘\(item.name)’. Tool: parse_resume with fileId \(item.id)")
        return item
    }

    @discardableResult
    func registerLinkedInProfile(url: URL) -> UploadedItem {
        let item = UploadedItem(
            id: UUID().uuidString,
            name: url.absoluteString,
            kind: .linkedInProfile,
            data: nil,
            url: url,
            createdAt: Date()
        )
        addUpload(item)
        appendSystemMessage("LinkedIn URL registered. Tool: parse_linkedin with url \(url.absoluteString)")
        return item
    }

    @discardableResult
    func registerArtifact(data: Data, suggestedName: String) -> UploadedItem {
        let item = UploadedItem(
            id: UUID().uuidString,
            name: suggestedName,
            kind: .artifact,
            data: data,
            url: nil,
            createdAt: Date()
        )
        addUpload(item)
        appendSystemMessage("Artifact ‘\(item.name)’ available. Tool: summarize_artifact with fileId \(item.id)")
        return item
    }

    private func addUpload(_ item: UploadedItem) {
        uploadsById[item.id] = item
        uploadedItems = uploadsById.values.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Response Handling

    private func handleLLMResponse(_ responseText: String) async throws {
        let parsed = try parseLLMOutput(responseText)

        if !parsed.assistantReply.isEmpty {
            messages.append(OnboardingMessage(role: .assistant, text: parsed.assistantReply))
        }

        if !parsed.deltaUpdates.isEmpty {
            try await applyDeltaUpdates(parsed.deltaUpdates)
        }

        if !parsed.knowledgeCards.isEmpty {
            _ = artifactStore.appendKnowledgeCards(parsed.knowledgeCards)
        }

        if let skillMap = parsed.skillMapDelta {
            _ = artifactStore.mergeSkillMap(patch: skillMap)
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

    private func processToolCalls(_ calls: [ToolCall]) async throws {
        guard let conversationId, let modelId else { return }

        var responses: [JSON] = []

        for call in calls where !processedToolIdentifiers.contains(call.identifier) {
            let result = try await executeTool(call)
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

    private func executeTool(_ call: ToolCall) async throws -> JSON {
        switch call.tool {
        case "parse_resume":
            return try executeParseResume(call)
        case "parse_linkedin":
            return try await executeParseLinkedIn(call)
        case "summarize_artifact":
            return try executeSummarizeArtifact(call)
        case "web_lookup":
            return try await executeWebLookup(call)
        case "persist_delta":
            try await executePersistDelta(call)
            return JSON(["status": "saved"])
        case "persist_card":
            try executePersistCard(call)
            return JSON(["status": "saved"])
        case "persist_skill_map":
            try executePersistSkillMap(call)
            return JSON(["status": "saved"])
        default:
            throw OnboardingError.unsupportedTool(call.tool)
        }
    }

    private func executeParseResume(_ call: ToolCall) throws -> JSON {
        guard let fileId = call.arguments["fileId"].string, let upload = uploadsById[fileId], let data = upload.data else {
            throw OnboardingError.missingResource("resume file")
        }

        let extraction = ResumeRawExtractor.extract(from: data, filename: upload.name)
        let uncertainties = ["education", "experience"].filter { extraction[$0].type == .null }

        pendingExtraction = PendingExtraction(rawExtraction: extraction, uncertainties: uncertainties)

        return JSON([
            "status": "awaiting_confirmation",
            "raw_extraction": extraction,
            "uncertainties": JSON(uncertainties)
        ])
    }

    private func executeParseLinkedIn(_ call: ToolCall) async throws -> JSON {
        if let directURL = call.arguments["url"].string, let url = URL(string: directURL) {
            let result = try await LinkedInProfileExtractor.extract(from: url)
            return JSON([
                "status": "complete",
                "raw_extraction": result.extraction,
                "uncertainties": JSON(result.uncertainties)
            ])
        }

        if let fileId = call.arguments["fileId"].string, let upload = uploadsById[fileId] {
            if let url = upload.url {
                let result = try await LinkedInProfileExtractor.extract(from: url)
                return JSON([
                    "status": "complete",
                    "raw_extraction": result.extraction,
                    "uncertainties": JSON(result.uncertainties)
                ])
            }
            if let data = upload.data, let string = String(data: data, encoding: .utf8) {
                let result = try LinkedInProfileExtractor.parse(html: string, source: upload.name)
                return JSON([
                    "status": "complete",
                    "raw_extraction": result.extraction,
                    "uncertainties": JSON(result.uncertainties)
                ])
            }
        }

        throw OnboardingError.missingResource("LinkedIn content")
    }

    private func executeSummarizeArtifact(_ call: ToolCall) throws -> JSON {
        guard let fileId = call.arguments["fileId"].string, let upload = uploadsById[fileId], let data = upload.data else {
            throw OnboardingError.missingResource("artifact data")
        }

        let context = call.arguments["context"].string
        let card = ArtifactSummarizer.summarize(data: data, filename: upload.name, context: context)
        _ = artifactStore.appendKnowledgeCards([card])
        refreshArtifacts()
        return card
    }

    private func executeWebLookup(_ call: ToolCall) async throws -> JSON {
        guard allowWebSearch else {
            throw OnboardingError.webSearchNotAllowed
        }
        guard let query = call.arguments["query"].string, !query.isEmpty else {
            throw OnboardingError.invalidArguments("Missing query for web_lookup")
        }

        let result = try await WebLookupService.search(query: query)
        return JSON([
            "results": JSON(result.entries),
            "notices": JSON(result.notices)
        ])
    }

    private func executePersistDelta(_ call: ToolCall) async throws {
        guard let target = call.arguments["target"].string else {
            throw OnboardingError.invalidArguments("persist_delta missing target")
        }
        let delta = call.arguments["delta"]
        try await applyPatch(target: target, patch: delta)
    }

    private func executePersistCard(_ call: ToolCall) throws {
        let card = call.arguments["card"]
        guard card.type == .dictionary else {
            throw OnboardingError.invalidArguments("persist_card expects card object")
        }
        _ = artifactStore.appendKnowledgeCards([card])
        refreshArtifacts()
    }

    private func executePersistSkillMap(_ call: ToolCall) throws {
        let delta = call.arguments["skillMapDelta"]
        guard delta.type == .dictionary else {
            throw OnboardingError.invalidArguments("persist_skill_map expects skillMapDelta object")
        }
        _ = artifactStore.mergeSkillMap(patch: delta)
        refreshArtifacts()
    }

    // MARK: - Artifact Helpers

    private func refreshArtifacts() {
        artifacts = artifactStore.loadArtifacts()
        refreshSchemaIssues()
    }

    private func refreshSchemaIssues() {
        var issues: [String] = []
        if let profile = artifacts.applicantProfile {
            let result = SchemaValidator.validateApplicantProfile(profile)
            issues.append(contentsOf: result.errors)
        }
        if let defaults = artifacts.defaultValues {
            let result = SchemaValidator.validateDefaultValues(defaults)
            issues.append(contentsOf: result.errors)
        }
        schemaIssues = issues
    }

    private func appendSystemMessage(_ text: String) {
        messages.append(OnboardingMessage(role: .system, text: text))
    }

    // MARK: - Delta Handling

    private func applyDeltaUpdates(_ updates: [JSON]) async throws {
        for update in updates {
            if let target = update["target"].string {
                let value = update["value"]
                try await applyPatch(target: target, patch: value)
            } else {
                let profilePatch = update["applicant_profile_patch"]
                if profilePatch.type != .null {
                    try await applyPatch(target: "applicant_profile", patch: profilePatch)
                }

                let defaultPatch = update["default_values_patch"]
                if defaultPatch.type != .null {
                    try await applyPatch(target: "default_values", patch: defaultPatch)
                }
            }
        }
    }

    private func applyPatch(target: String, patch: JSON) async throws {
        let normalized = target.lowercased()
        switch normalized {
        case "applicant_profile":
            let merged = artifactStore.mergeApplicantProfile(patch: patch)
            applyApplicantProfilePatch(merged)
        case "default_values":
            _ = artifactStore.mergeDefaultValues(patch: patch)
        case "skill_map", "skills_index":
            _ = artifactStore.mergeSkillMap(patch: patch)
        default:
            Logger.warning("OnboardingInterviewService: unhandled delta target \(target)")
        }
        refreshArtifacts()
    }

    private func applyApplicantProfilePatch(_ patch: JSON) {
        guard patch.type == .dictionary else { return }

        let profile = applicantProfileStore.currentProfile()

        if let name = patch["name"].string { profile.name = name }
        if let address = patch["address"].string { profile.address = address }
        if let city = patch["city"].string { profile.city = city }
        if let state = patch["state"].string { profile.state = state }
        if let zip = patch["zip"].string { profile.zip = zip }
        if let phone = patch["phone"].string { profile.phone = phone }
        if let email = patch["email"].string { profile.email = email }
        if let website = patch["website"].string { profile.websites = website }

        if let signatureBase64 = patch["signature_image"].string,
           let data = Data(base64Encoded: signatureBase64) {
            profile.signatureData = data
        }

        applicantProfileStore.save(profile)
    }

    // MARK: - Parsing

    private struct ParsedLLMOutput {
        let assistantReply: String
        let deltaUpdates: [JSON]
        let knowledgeCards: [JSON]
        let skillMapDelta: JSON?
        let profileContext: String?
        let needsVerification: [String]
        let nextQuestions: [OnboardingQuestion]
        let toolCalls: [ToolCall]
    }

    private func parseLLMOutput(_ text: String) throws -> ParsedLLMOutput {
        guard let json = extractJSON(from: text) else {
            throw OnboardingError.invalidResponseFormat
        }

        let assistantReply = json["assistant_reply"].string ??
            json["assistant_message"].string ??
            text.trimmingCharacters(in: .whitespacesAndNewlines)

        var deltaUpdates: [JSON] = []
        if let array = json["delta_update"].array {
            deltaUpdates = array
        } else if json["delta_update"].type == .dictionary {
            deltaUpdates = [json["delta_update"]]
        }

        let knowledgeCards = json["knowledge_cards"].arrayValue
        let skillMapDelta: JSON? = json["skill_map_delta"].type == .null ? nil : json["skill_map_delta"]
        let profileContext = json["profile_context"].string
        let needsVerification = json["needs_verification"].arrayValue.compactMap { $0.string }

        let questions = json["next_questions"].arrayValue.compactMap { item -> OnboardingQuestion? in
            guard let id = item["id"].string ?? item["title"].string else { return nil }
            let text = item["question"].string ?? item["text"].string ?? ""
            if text.isEmpty { return nil }
            return OnboardingQuestion(id: id, text: text)
        }

        let toolCalls = json["tool_calls"].arrayValue.compactMap { item -> ToolCall? in
            guard let name = item["tool"].string else { return nil }
            let identifier = item["id"].string ?? UUID().uuidString
            return ToolCall(identifier: identifier, tool: name, arguments: item["args"])
        }

        return ParsedLLMOutput(
            assistantReply: assistantReply,
            deltaUpdates: deltaUpdates,
            knowledgeCards: knowledgeCards,
            skillMapDelta: skillMapDelta,
            profileContext: profileContext,
            needsVerification: needsVerification,
            nextQuestions: questions,
            toolCalls: toolCalls
        )
    }

    private func extractJSON(from text: String) -> JSON? {
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")

        if let data = cleaned.data(using: .utf8),
           let json = try? JSON(data: data), json.type != .null {
            return json
        }

        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}") else {
            return nil
        }

        let substring = cleaned[start...end]
        if let data = String(substring).data(using: .utf8),
           let json = try? JSON(data: data), json.type != .null {
            return json
        }

        return nil
    }

    // MARK: - Errors

    enum OnboardingError: Error, LocalizedError {
        case backendUnsupported
        case invalidResponseFormat
        case unsupportedTool(String)
        case missingResource(String)
        case invalidArguments(String)
        case webSearchNotAllowed

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
            }
        }
    }
}

private enum PromptBuilder {
    static func systemPrompt() -> String {
        """
        SYSTEM
        ────────────────────────────────────────────
        You are the Onboarding Interviewer for a résumé app.
        Your mission is to transform a live conversation into verified, schema-driven artifacts that power job search automation.

        OPERATING PRINCIPLES
        - Coach first, then extract structured data. Encourage storytelling, metrics, and evidence.
        - Never persist unconfirmed information. Mark uncertainties in needs_verification until resolved.
        - Respect phase directives delivered as JSON objects with "type": "phase_transition". Switch goals immediately when received.
        - Keep the conversation tight: summarize, checkpoint, and synthesize to avoid runaway context.

        PHASE PROTOCOL
        1. Core Facts — Confirm identity details and establish the default résumé structure (ApplicantProfile + DefaultValues).
        2. Deep Dive — Elicit narrative evidence, produce knowledge_cards, and extend the skills_index with verifiable metrics.
        3. Personal Context — Capture goals, preferences, constraints, and clear any outstanding gaps before handoff.

        CONTROL SIGNALS
        - phase_transition directives arrive as JSON and outline the current phase, focus, and expected outputs—adjust your plan immediately.
        - web_search_consent messages communicate whether outbound web lookups are permitted; never call web_lookup when allowed is false.

        TOOLBOX
        - parse_resume {fileId}: parse uploaded résumé data. Always confirm extractions with the user.
        - parse_linkedin {url|fileId}: ingest a LinkedIn profile (HTML or URL) and highlight uncertain fields.
        - summarize_artifact {fileId, context?}: produce a knowledge card for supporting materials (projects, papers, decks).
        - web_lookup {query, context?}: confirm public references (only when the user has granted consent).
        - persist_delta / persist_card / persist_skill_map: save user-confirmed changes to local artifacts.

        OUTPUT CONTRACT
        Every response must be a single JSON object containing:
        {
          "assistant_reply": String,
          "delta_update": [ { "target": "...", "value": {...} } ]?,
          "knowledge_cards": [ {...} ]?,
          "skill_map_delta": { ... }?,
          "profile_context": String?,
          "needs_verification": [ String ]?,
          "next_questions": [ { "id": String, "question": String, "target": String? } ]?,
          "tool_calls": [ { "id": String, "tool": String, "args": Object } ]?
        }
        Do not emit freeform prose outside this object.

        INTERVIEW STYLE
        - Ask for the latest résumé PDF or LinkedIn URL immediately when none is confirmed.
        - Confirm extracted fields aloud and invite corrections before persisting.
        - Demand quantification: numbers, percentages, dollars, before/after states, collaborators, and scope.
        - Invite uploads or URLs for supporting artifacts; summarize them with summarize_artifact when provided.
        - Seek user consent before web_lookup calls and disclose any external gathering you perform.
        """
    }

    static func kickoffMessage(with artifacts: OnboardingArtifacts, phase: OnboardingPhase) -> String {
        var message = "We are beginning an onboarding interview."

        if let profile = artifacts.applicantProfile, let raw = profile.rawString(options: []) {
            message += "\nCurrent applicant_profile JSON: \(raw)"
        }
        if let defaults = artifacts.defaultValues, let raw = defaults.rawString(options: []) {
            message += "\nCurrent default_values JSON: \(raw)"
        }
        if !artifacts.knowledgeCards.isEmpty,
           let raw = JSON(artifacts.knowledgeCards).rawString(options: []) {
            message += "\nExisting knowledge_cards: \(raw)"
        }
        if let skillMap = artifacts.skillMap, let raw = skillMap.rawString(options: []) {
            message += "\nExisting skills_index: \(raw)"
        }
        if let context = artifacts.profileContext {
            message += "\nCurrent profile_context: \(context)"
        }

        let directive = phaseDirective(for: phase)
        if let directiveText = directive.rawString(options: [.sortedKeys]) {
            message += "\nActive phase directive: \(directiveText)"
        }
        message += "\nFocus summary: \(phase.focusSummary)"
        message += "\nExpected outputs: \(phase.expectedOutputs.joined(separator: " | "))"

        message += "\nPlease greet the user, request their latest résumé or LinkedIn URL, and ask any clarifying opening question."
        return message
    }

    static func resumeMessage(with artifacts: OnboardingArtifacts, phase: OnboardingPhase) -> String {
        var message = "We are resuming the onboarding interview."

        if let profile = artifacts.applicantProfile, let raw = profile.rawString(options: []) {
            message += "\nCurrent applicant_profile JSON: \(raw)"
        }
        if let defaults = artifacts.defaultValues, let raw = defaults.rawString(options: []) {
            message += "\nCurrent default_values JSON: \(raw)"
        }
        if !artifacts.knowledgeCards.isEmpty,
           let raw = JSON(artifacts.knowledgeCards).rawString(options: []) {
            message += "\nExisting knowledge_cards: \(raw)"
        }
        if let skillMap = artifacts.skillMap, let raw = skillMap.rawString(options: []) {
            message += "\nExisting skills_index: \(raw)"
        }
        if let context = artifacts.profileContext {
            message += "\nCurrent profile_context: \(context)"
        }
        if !artifacts.needsVerification.isEmpty,
           let raw = JSON(artifacts.needsVerification).rawString(options: []) {
            message += "\nOutstanding needs_verification: \(raw)"
        }

        let directive = phaseDirective(for: phase)
        if let directiveText = directive.rawString(options: [.sortedKeys]) {
            message += "\nActive phase directive: \(directiveText)"
        }
        message += "\nFocus summary: \(phase.focusSummary)"

        message += "\nPlease provide a concise recap of confirmed progress, recap open needs_verification items, and continue with the next best questions for this phase."
        return message
    }

    static func phaseDirective(for phase: OnboardingPhase) -> JSON {
        JSON([
            "type": "phase_transition",
            "phase": phase.rawValue,
            "focus": phase.focusSummary,
            "expected_outputs": JSON(phase.expectedOutputs),
            "interview_prompts": JSON(phase.interviewPrompts)
        ])
    }
}
