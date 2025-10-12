import Foundation
import Observation
import SwiftyJSON

@MainActor
@Observable
final class OnboardingInterviewService {
    enum Backend: CaseIterable {
        case openRouter
        case openAI

        var displayName: String {
            switch self {
            case .openRouter: return "OpenRouter"
            case .openAI: return "OpenAI"
            }
        }

        var isAvailable: Bool {
            switch self {
            case .openRouter: return true
            case .openAI: return false
            }
        }
    }

    private let llmFacade: LLMFacade
    private let artifactStore: OnboardingArtifactStore
    private let applicantProfileStore: ApplicantProfileStore

    private(set) var artifacts: OnboardingArtifacts
    private(set) var messages: [OnboardingMessage] = []
    private(set) var nextQuestions: [OnboardingQuestion] = []
    private(set) var currentPhase: OnboardingPhase = .coreFacts
    private(set) var isProcessing = false
    private(set) var isActive = false
    private(set) var lastError: String?

    private var conversationId: UUID?
    private var modelId: String?
    private var backend: Backend = .openRouter

    init(
        llmFacade: LLMFacade,
        artifactStore: OnboardingArtifactStore,
        applicantProfileStore: ApplicantProfileStore
    ) {
        self.llmFacade = llmFacade
        self.artifactStore = artifactStore
        self.applicantProfileStore = applicantProfileStore
        self.artifacts = artifactStore.loadArtifacts()
    }

    func reset() {
        messages.removeAll()
        nextQuestions.removeAll()
        conversationId = nil
        modelId = nil
        backend = .openRouter
        isActive = false
        isProcessing = false
        lastError = nil
        artifacts = artifactStore.loadArtifacts()
        currentPhase = .coreFacts
    }

    func setPhase(_ phase: OnboardingPhase) {
        currentPhase = phase
    }

    func startInterview(modelId: String, backend: Backend = .openRouter) async {
        reset()
        self.modelId = modelId
        self.backend = backend
        isProcessing = true
        lastError = nil

        do {
            guard backend == .openRouter else {
                throw OnboardingError.backendUnsupported
            }

            let systemPrompt = PromptBuilder.systemPrompt()
            let kickoff = PromptBuilder.kickoffMessage(with: artifacts)

            let (conversationId, response) = try await llmFacade.startConversation(
                systemPrompt: systemPrompt,
                userMessage: kickoff,
                modelId: modelId
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
                conversationId: conversationId
            )
            try await handleLLMResponse(response)
        } catch {
            lastError = error.localizedDescription
            Logger.error("OnboardingInterviewService.send failed: \(error)")
        }

        isProcessing = false
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

        artifacts = artifactStore.loadArtifacts()
        nextQuestions = parsed.nextQuestions
    }

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
        var assistantReply: String
        var deltaUpdates: [JSON]
        var knowledgeCards: [JSON]
        var skillMapDelta: JSON?
        var profileContext: String?
        var needsVerification: [String]
        var nextQuestions: [OnboardingQuestion]
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

        let questions = json["next_questions"].arrayValue.map { item -> OnboardingQuestion? in
            guard let id = item["id"].string ?? item["title"].string else { return nil }
            let text = item["question"].string ?? item["text"].string ?? ""
            if text.isEmpty { return nil }
            let target = item["target"].string ?? item["field"].string
            return OnboardingQuestion(id: id, text: text, target: target)
        }.compactMap { $0 }

        return ParsedLLMOutput(
            assistantReply: assistantReply,
            deltaUpdates: deltaUpdates,
            knowledgeCards: knowledgeCards,
            skillMapDelta: skillMapDelta,
            profileContext: profileContext,
            needsVerification: needsVerification,
            nextQuestions: questions
        )
    }

    private func extractJSON(from text: String) -> JSON? {
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")

        if let data = cleaned.data(using: .utf8), let json = try? JSON(data: data), json.type != .null {
            return json
        }

        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}") else {
            return nil
        }

        let substring = cleaned[start...end]
        if let data = String(substring).data(using: .utf8), let json = try? JSON(data: data), json.type != .null {
            return json
        }

        return nil
    }

    // MARK: - Prompt Builder

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

    // MARK: - Errors

    enum OnboardingError: LocalizedError {
        case backendUnsupported
        case invalidResponseFormat

        var errorDescription: String? {
            switch self {
            case .backendUnsupported:
                return "Selected backend is not supported in this build."
            case .invalidResponseFormat:
                return "Assistant response was not valid JSON."
            }
        }
    }
}
