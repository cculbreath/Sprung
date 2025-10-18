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
            case writingSample
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
    private let coverRefStore: CoverRefStore?
    private let openAIConversationService: OpenAIResponsesConversationService?

    private var conversationId: UUID?
    private var modelId: String?
    private var backend: LLMFacade.Backend = .openRouter

    private var uploadsById: [String: UploadedItem] = [:]
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
    private(set) var pendingExtraction: PendingExtraction?
    private(set) var uploadedItems: [UploadedItem] = []
    private(set) var schemaIssues: [String] = []

    init(
        llmFacade: LLMFacade,
        artifactStore: OnboardingArtifactStore,
        applicantProfileStore: ApplicantProfileStore,
        coverRefStore: CoverRefStore? = nil,
        openAIConversationService: OpenAIResponsesConversationService? = nil
    ) {
        self.llmFacade = llmFacade
        self.artifactStore = artifactStore
        self.applicantProfileStore = applicantProfileStore
        self.coverRefStore = coverRefStore
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
        allowWritingAnalysis = false
        processedToolIdentifiers.removeAll()
        refreshArtifacts()
        currentPhase = .resumeIntake
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

    @discardableResult
    func registerWritingSample(data: Data, suggestedName: String) -> UploadedItem {
        let item = UploadedItem(
            id: UUID().uuidString,
            name: suggestedName,
            kind: .writingSample,
            data: data,
            url: nil,
            createdAt: Date()
        )
        addUpload(item)
        appendSystemMessage("Writing sample ‘\(item.name)’ ready. Tool: summarize_writing or persist_style_profile will reference fileId \(item.id)")
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
            _ = artifactStore.saveWritingSamples(parsed.writingSamples)
            persistWritingSamplesToCoverRefs(samples: parsed.writingSamples)
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
        case "summarize_writing":
            return try executeSummarizeWriting(call)
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
        case "persist_facts_from_card":
            try executePersistFactsFromCard(call)
            return JSON(["status": "saved"])
        case "persist_style_profile":
            try executePersistStyleProfile(call)
            return JSON(["status": "saved"])
        case "verify_conflicts":
            return try executeVerifyConflicts(call)
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

    private func executeSummarizeWriting(_ call: ToolCall) throws -> JSON {
        guard allowWritingAnalysis else {
            throw OnboardingError.writingAnalysisNotAllowed
        }
        guard let fileId = call.arguments["fileId"].string,
              let upload = uploadsById[fileId],
              let data = upload.data else {
            throw OnboardingError.missingResource("writing sample data")
        }

        let context = call.arguments["context"].string
        let summary = WritingSampleAnalyzer.analyze(
            data: data,
            filename: upload.name,
            context: context,
            sampleId: fileId
        )
        _ = artifactStore.saveWritingSamples([summary])
        refreshArtifacts()
        return summary
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

    private func executePersistFactsFromCard(_ call: ToolCall) throws {
        let factsArray = call.arguments["facts"].array ?? call.arguments["entries"].array ?? call.arguments["fact_ledger"].array ?? []
        guard !factsArray.isEmpty else {
            throw OnboardingError.invalidArguments("persist_facts_from_card expects non-empty facts array")
        }

        let validation = SchemaValidator.validateFactLedger(factsArray)
        guard validation.errors.isEmpty else {
            throw OnboardingError.invalidArguments("Fact ledger validation failed: \(validation.errors.joined(separator: "; "))")
        }

        _ = artifactStore.appendFactLedgerEntries(factsArray)
        refreshArtifacts()
    }

    private func executePersistStyleProfile(_ call: ToolCall) throws {
        guard allowWritingAnalysis else {
            throw OnboardingError.writingAnalysisNotAllowed
        }

        let styleVector = call.arguments["style_vector"]
        guard styleVector.type == .dictionary else {
            throw OnboardingError.invalidArguments("Style profile requires style_vector object")
        }

        let samplesJSON = call.arguments["samples"]
        guard let sampleArray = samplesJSON.array, !sampleArray.isEmpty else {
            throw OnboardingError.invalidArguments("Style profile requires at least one writing sample reference")
        }

        var payloadDictionary: [String: Any] = [:]
        payloadDictionary["style_vector"] = styleVector.dictionaryObject ?? styleVector.object
        payloadDictionary["samples"] = samplesJSON.arrayObject ?? []

        let payload = JSON(payloadDictionary)
        let validation = SchemaValidator.validateStyleProfile(payload)
        guard validation.errors.isEmpty else {
            throw OnboardingError.invalidArguments("Style profile validation failed: \(validation.errors.joined(separator: "; "))")
        }

        artifactStore.saveStyleProfile(payload)

        _ = artifactStore.saveWritingSamples(sampleArray)
        persistWritingSamplesToCoverRefs(samples: sampleArray)

        refreshArtifacts()
    }

    private func persistWritingSamplesToCoverRefs(samples: [JSON]) {
        guard let coverRefStore else { return }
        var didPersist = false

        for sample in samples {
            guard let sampleId = sample["sample_id"].string ?? sample["id"].string,
                  let upload = uploadsById[sampleId],
                  let data = upload.data else {
                continue
            }

            let name = sample["title"].string ??
                sample["name"].string ??
                upload.name
            let content = WritingSampleAnalyzer.extractPlainText(from: data)
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            if let existing = coverRefStore.storedCoverRefs.first(where: { $0.id == sampleId }) {
                existing.content = content
                existing.name = name
                didPersist = coverRefStore.saveContext() || didPersist
            } else {
                let newRef = CoverRef(name: name, content: content, enabledByDefault: false, type: .writingSample)
                newRef.id = sampleId
                coverRefStore.addCoverRef(newRef)
                didPersist = true
            }
        }

        if didPersist {
            Logger.info("✅ Persisted writing samples to CoverRef store.")
        }
    }

    private func executeVerifyConflicts(_ call: ToolCall) throws -> JSON {
        let latest = artifactStore.loadArtifacts()
        guard let defaultValues = latest.defaultValues else {
            return JSON([
                "status": "complete",
                "conflicts": []
            ])
        }

        let conflicts = detectTimelineConflicts(in: defaultValues)
        let status = conflicts.isEmpty ? "none" : "conflicts_found"
        return JSON([
            "status": status,
            "conflicts": JSON(conflicts)
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
        if !artifacts.factLedger.isEmpty {
            let result = SchemaValidator.validateFactLedger(artifacts.factLedger)
            issues.append(contentsOf: result.errors)
        }
        if let styleProfile = artifacts.styleProfile {
            let result = SchemaValidator.validateStyleProfile(styleProfile)
            issues.append(contentsOf: result.errors)
        }
        if !artifacts.writingSamples.isEmpty {
            let result = SchemaValidator.validateWritingSamples(artifacts.writingSamples)
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
        case "fact_ledger":
            if let entries = patch.array {
                _ = artifactStore.appendFactLedgerEntries(entries)
            }
        case "style_profile":
            artifactStore.saveStyleProfile(patch)
        case "writing_samples":
            if let entries = patch.array {
                _ = artifactStore.saveWritingSamples(entries)
            }
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

    private func detectTimelineConflicts(in defaultValues: JSON) -> [JSON] {
        let employment = defaultValues["employment"].arrayValue
        struct EmploymentInterval {
            let identifier: String
            let title: String
            let company: String
            let startDate: Date
            let startRaw: String
            let endDate: Date?
            let endRaw: String?
        }

        var intervals: [EmploymentInterval] = []

        for (index, job) in employment.enumerated() {
            let identifier = job["id"].string ?? "employment[\(index)]"
            let title = job["title"].string ?? "Role"
            let company = job["company"].string ?? "Company"
            let startRaw = job["start_date"].string ??
                job["start"].string ??
                job["timeline"]["start"].string ?? ""
            guard
                let startDate = parsePartialDate(from: startRaw)
            else { continue }

            let endRaw = job["end_date"].string ??
                job["end"].string ??
                job["timeline"]["end"].string
            let endDate = parsePartialDate(from: endRaw)

            let interval = EmploymentInterval(
                identifier: identifier,
                title: title,
                company: company,
                startDate: startDate,
                startRaw: startRaw,
                endDate: endDate,
                endRaw: endRaw
            )
            intervals.append(interval)
        }

        guard intervals.count > 1 else { return [] }

        var conflicts: [JSON] = []
        for i in 0..<(intervals.count - 1) {
            for j in (i + 1)..<intervals.count {
                let first = intervals[i]
                let second = intervals[j]

                let firstEnd = first.endDate ?? .distantFuture
                let secondEnd = second.endDate ?? .distantFuture

                let rangesOverlap = first.startDate <= secondEnd && second.startDate <= firstEnd
                guard rangesOverlap else { continue }

                let entryPayload: [String: Any] = [
                    "type": "timeline_overlap",
                    "entries": [
                        [
                            "id": first.identifier,
                            "title": first.title,
                            "company": first.company,
                            "range": formattedRange(startRaw: first.startRaw, endRaw: first.endRaw)
                        ],
                        [
                            "id": second.identifier,
                            "title": second.title,
                            "company": second.company,
                            "range": formattedRange(startRaw: second.startRaw, endRaw: second.endRaw)
                        ]
                    ],
                    "message": "Employment entries for \(first.title) @ \(first.company) and \(second.title) @ \(second.company) overlap. Confirm whether the roles were concurrent or adjust the timeline.",
                    "suggested_fix": "Verify start/end months and ensure at most one role per interval unless positions were concurrent."
                ]
                conflicts.append(JSON(entryPayload))
            }
        }

        return conflicts
    }

    private func parsePartialDate(from value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        if let date = isoFormatter.date(from: value) {
            return date
        }

        if value.count == 7, value.contains("-") {
            let components = value.split(separator: "-")
            if components.count == 2,
               let year = Int(components[0]),
               let month = Int(components[1]) {
                var dateComponents = DateComponents()
                dateComponents.year = year
                dateComponents.month = month
                dateComponents.day = 1
                return Calendar.current.date(from: dateComponents)
            }
        }

        if value.count == 4, let year = Int(value) {
            var dateComponents = DateComponents()
            dateComponents.year = year
            dateComponents.month = 1
            dateComponents.day = 1
            return Calendar.current.date(from: dateComponents)
        }

        return nil
    }

    private func formattedRange(startRaw: String, endRaw: String?) -> String {
        let startDisplay = startRaw.isEmpty ? "?" : startRaw
        let endDisplay = endRaw?.isEmpty == false ? endRaw! : "Present"
        return "\(startDisplay) – \(endDisplay)"
    }

    // MARK: - Parsing

    private struct ParsedLLMOutput {
        let assistantReply: String
        let deltaUpdates: [JSON]
        let knowledgeCards: [JSON]
        let factLedgerEntries: [JSON]
        let skillMapDelta: JSON?
        let styleProfile: JSON?
        let writingSamples: [JSON]
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
        let factLedgerEntries = json["fact_ledger"].arrayValue
        let skillMapDelta: JSON? = json["skill_map_delta"].type == .null ? nil : json["skill_map_delta"]
        let styleProfile: JSON? = json["style_profile"].type == .null ? nil : json["style_profile"]
        let writingSamples = json["writing_samples"].arrayValue
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
            factLedgerEntries: factLedgerEntries,
            skillMapDelta: skillMapDelta,
            styleProfile: styleProfile,
            writingSamples: writingSamples,
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

private enum PromptBuilder {
    static func systemPrompt() -> String {
        """
        You are the LLM interviewer for Sprung, a résumé and cover-letter customization app.

        OBJECTIVE
        Lead the user through an artifact-first onboarding workflow that captures:
        1. ApplicantProfile and DefaultValues parsed from a résumé or LinkedIn profile.
        2. Artifact summaries (ResRefs), fact ledger entries, and skill→evidence mappings.
        3. Writing samples analysed into a style_vector, with full texts persisted separately.

        RULES
        - Emit exactly one JSON object per turn with the schema below; no extra prose.
        - Prefer asking for concrete artifacts (uploads or URLs) before relying on conversation.
        - Request confirmations before invoking persistence tools.
        - Respect consent signals: web and writing-style analysis only proceed when explicitly allowed.
        - Mark unresolved items under needs_verification with short descriptions.

        TOOLS
        - parse_resume {fileId}: Parse résumé uploads into ApplicantProfile + DefaultValues.
        - parse_linkedin {url|fileId}: Extract data from LinkedIn URLs or HTML exports.
        - summarize_artifact {fileId, context?}: Generate a ResRef knowledge card for supporting materials.
        - summarize_writing {fileId, context?}: Analyse writing samples to produce style metrics (requires opt-in).
        - web_lookup {query, context?}: Perform web research only if consented.
        - verify_conflicts {}: Ask the host app to check for timeline overlaps or data issues.
        - persist_delta {target, delta}: Commit confirmed patches to ApplicantProfile, DefaultValues, or related structures.
        - persist_card {card}: Persist a verified ResRef/knowledge card.
        - persist_facts_from_card {facts}: Add validated entries to the fact ledger.
        - persist_skill_map {skillMapDelta}: Merge confirmed skill↔evidence updates.
        - persist_style_profile {samples, style_vector}: Save style profile metrics and register samples (requires opt-in).

        OUTPUT JSON CONTRACT
        {
          "assistant_reply": String,
          "delta_update": [ { "target": String, "value": Any } ]?,
          "knowledge_cards": [ Object ]?,
          "fact_ledger": [ Object ]?,
          "skill_map_delta": Object?,
          "profile_context": String?,
          "needs_verification": [ String ]?,
          "next_questions": [ { "id": String, "question": String, "target": String? } ]?,
          "tool_calls": [ { "id": String, "tool": String, "args": Object } ]?
        }
        Use null instead of omitting when a field applies but no data is available. Never emit multiple JSON blocks.

        STYLE
        - Be concise and conversational (≤4 follow-ups per topic).
        - Coach the user toward quantified, verifiable statements.
        - Surface opportunities to upload artifacts or writing samples at each phase.
        - Summarize progress regularly and highlight remaining uncertainties.
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
        if !artifacts.factLedger.isEmpty,
           let raw = JSON(artifacts.factLedger).rawString(options: []) {
            message += "\nExisting fact_ledger entries: \(raw)"
        }
        if let styleProfile = artifacts.styleProfile,
           let raw = styleProfile.rawString(options: []) {
            message += "\nExisting style_profile: \(raw)"
        }
        if !artifacts.writingSamples.isEmpty,
           let raw = JSON(artifacts.writingSamples).rawString(options: []) {
            message += "\nKnown writing_samples: \(raw)"
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
        if !artifacts.factLedger.isEmpty,
           let raw = JSON(artifacts.factLedger).rawString(options: []) {
            message += "\nExisting fact_ledger entries: \(raw)"
        }
        if let styleProfile = artifacts.styleProfile,
           let raw = styleProfile.rawString(options: []) {
            message += "\nExisting style_profile: \(raw)"
        }
        if !artifacts.writingSamples.isEmpty,
           let raw = JSON(artifacts.writingSamples).rawString(options: []) {
            message += "\nKnown writing_samples: \(raw)"
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
