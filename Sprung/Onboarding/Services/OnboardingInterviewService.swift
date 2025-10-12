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

    struct PendingExtraction: Sendable {
        let fileId: String
        var rawExtraction: JSON
        var uncertainties: [String]
    }

    private struct ToolCall: Sendable {
        let identifier: String
        let tool: String
        let arguments: JSON
    }

    private let llmFacade: LLMFacade
    private let artifactStore: OnboardingArtifactStore
    private let applicantProfileStore: ApplicantProfileStore

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
        applicantProfileStore: ApplicantProfileStore
    ) {
        self.llmFacade = llmFacade
        self.artifactStore = artifactStore
        self.applicantProfileStore = applicantProfileStore
        self.artifacts = artifactStore.loadArtifacts()
        refreshSchemaIssues()
    }

    // MARK: - Backend Availability

    func availableBackends() -> [LLMFacade.Backend] {
        llmFacade.availableBackends()
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
        currentPhase = phase
    }

    func setWebSearchConsent(_ isAllowed: Bool) {
        allowWebSearch = isAllowed
    }

    func startInterview(modelId: String, backend: LLMFacade.Backend = .openRouter) async {
        reset()
        self.modelId = modelId
        self.backend = backend
        isProcessing = true
        lastError = nil

        do {
            let systemPrompt = PromptBuilder.systemPrompt()
            let kickoff = PromptBuilder.kickoffMessage(with: artifacts)

            let (conversationId, response) = try await llmFacade.startConversation(
                systemPrompt: systemPrompt,
                userMessage: kickoff,
                modelId: modelId,
                backend: backend
            )
            self.conversationId = conversationId
            try await handleLLMResponse(response)
            isActive = true
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
    }

    private func processToolCalls(_ calls: [ToolCall]) async throws {
        guard let conversationId, let modelId else { return }

        var responses: [JSON] = []

        for call in calls where !processedToolIdentifiers.contains(call.identifier) {
            let result = try await executeTool(call)
            processedToolIdentifiers.insert(call.identifier)
            var payload: [String: Any] = [
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

        pendingExtraction = PendingExtraction(fileId: fileId, rawExtraction: extraction, uncertainties: uncertainties)

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
            let target = item["target"].string ?? item["field"].string
            return OnboardingQuestion(id: id, text: text, target: target)
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
        You are the **Onboarding Interviewer** for a résumé app.
        Your role is to collect verified applicant information, elicit professional stories, and build structured, evidence-backed data artifacts.

        Always respond with a strict JSON object containing:
        - "assistant_reply": natural-language reply for the user
        - "delta_update": optional array describing patches to apply (each item may contain {"target": "applicant_profile"|"default_values", "value": {...}})
        - "knowledge_cards": optional array of knowledge card objects
        - "skill_map_delta": optional JSON object of skill-to-evidence updates
        - "profile_context": optional string summarizing goals/constraints
        - "needs_verification": optional array of strings
        - "next_questions": optional array with objects {"id", "question", "target"}
        - "tool_calls": optional array with objects {"id", "tool", "args"}

        Objectives:
        1. Populate ApplicantProfile and DefaultValues schemas.
        2. Generate knowledge cards, profile context, and skill evidence map.
        3. Use schema-conformant JSON in all updates.
        4. Mark uncertain data in "needs_verification".
        """
    }

    static func kickoffMessage(with artifacts: OnboardingArtifacts) -> String {
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

        message += "\nPlease greet the user, request their latest résumé or LinkedIn URL, and ask any clarifying opening question."
        return message
    }
}
