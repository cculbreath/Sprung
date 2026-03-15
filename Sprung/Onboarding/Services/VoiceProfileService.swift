//
//  VoiceProfileService.swift
//  Sprung
//
//  Extracts voice characteristics from writing samples during Phase 1.
//

import Foundation
import SwiftOpenAI

/// Extracts voice characteristics from writing samples.
/// Called after Phase 1 writing sample collection completes.
@MainActor
final class VoiceProfileService {
    private var llmFacade: LLMFacade?
    private let reasoningStreamManager: ReasoningStreamManager
    private var activeStreamingHandle: LLMStreamingHandle?

    private func getModelId() throws -> String {
        guard let modelId = UserDefaults.standard.string(forKey: "voiceProfileModelId"), !modelId.isEmpty else {
            throw ModelConfigurationError.modelNotConfigured(
                settingKey: "voiceProfileModelId",
                operationName: "Voice Profile Generation"
            )
        }
        return modelId
    }

    init(llmFacade: LLMFacade?, reasoningStreamManager: ReasoningStreamManager) {
        self.llmFacade = llmFacade
        self.reasoningStreamManager = reasoningStreamManager
    }

    func updateLLMFacade(_ facade: LLMFacade?) {
        self.llmFacade = facade
    }

    /// Extract voice profile from writing samples
    func extractVoiceProfile(from samples: [String]) async throws -> VoiceProfile {
        guard let facade = llmFacade else {
            throw VoiceProfileError.llmNotConfigured
        }

        guard !samples.isEmpty else {
            Logger.warning("🎤 No writing samples provided, returning default profile", category: .ai)
            return VoiceProfile()
        }

        let modelId = try getModelId()
        let samplesText = samples.joined(separator: "\n\n---\n\n")
        let prompt = PromptLibrary.substitute(
            template: PromptLibrary.voiceProfileTemplate,
            replacements: ["WRITING_SAMPLES": samplesText]
        )

        Logger.info("🎤 Extracting voice profile from \(samples.count) samples", category: .ai)

        let jsonSchema = try JSONSchema.from(dictionary: VoiceProfileSchemas.schema)
        let userEffort = UserDefaults.standard.string(forKey: "reasoningEffort") ?? "medium"
        let reasoning = OpenRouterReasoning(effort: userEffort, includeReasoning: true)

        activeStreamingHandle?.cancel()
        reasoningStreamManager.clear()
        reasoningStreamManager.startReasoning(modelName: modelId)

        do {
            let handle = try await facade.startConversationStreaming(
                userMessage: prompt,
                modelId: modelId,
                reasoning: reasoning,
                jsonSchema: jsonSchema
            )
            activeStreamingHandle = handle

            var fullResponse = ""
            var collectingJSON = false
            var jsonResponse = ""

            for try await chunk in handle.stream {
                if let reasoningContent = chunk.allReasoningText {
                    reasoningStreamManager.reasoningText += reasoningContent
                }
                if let content = chunk.content {
                    fullResponse += content
                    if content.contains("{") || collectingJSON {
                        collectingJSON = true
                        jsonResponse += content
                    }
                }
                if chunk.isFinished {
                    reasoningStreamManager.isStreaming = false
                    reasoningStreamManager.isVisible = false
                }
            }

            activeStreamingHandle = nil

            let responseText = jsonResponse.isEmpty ? fullResponse : jsonResponse
            let profile: VoiceProfile = try JSONResponseParser.parseText(responseText, as: VoiceProfile.self)

            Logger.info(
                "🎤 Extracted voice profile: \(profile.enthusiasm.displayName), first person: \(profile.useFirstPerson)",
                category: .ai
            )
            return profile
        } catch {
            activeStreamingHandle = nil
            reasoningStreamManager.isStreaming = false
            reasoningStreamManager.isVisible = false
            throw error
        }
    }

    /// Store extracted voice profile in guidance store
    func storeVoiceProfile(_ profile: VoiceProfile, in guidanceStore: InferenceGuidanceStore) {
        let attachments = GuidanceAttachments(voiceProfile: profile)

        let guidance = InferenceGuidance(
            nodeKey: "objective",
            displayName: "Voice Profile",
            prompt: """
            Voice profile for content generation:
            - Enthusiasm: \(profile.enthusiasm.displayName)
            - Person: \(profile.useFirstPerson ? "First person (I built, I discovered)" : "Third person")
            - Connectives: \(profile.connectiveStyle)
            - Aspirational phrases: \(profile.aspirationalPhrases.joined(separator: ", "))
            - NEVER use: \(profile.avoidPhrases.joined(separator: ", "))

            Sample excerpts preserving voice:
            \(profile.sampleExcerpts.map { "• \"\($0)\"" }.joined(separator: "\n"))
            """,
            attachmentsJSON: attachments.asJSON(),
            source: .auto
        )

        guidanceStore.add(guidance)
        Logger.info("🎤 Voice profile stored in guidance store", category: .ai)
    }

    enum VoiceProfileError: Error, LocalizedError {
        case llmNotConfigured

        var errorDescription: String? {
            switch self {
            case .llmNotConfigured:
                return "LLM facade not configured"
            }
        }
    }
}

private enum VoiceProfileSchemas {
    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "enthusiasm": [
                "type": "string",
                "enum": ["measured", "moderate", "high"],
                "description": "Overall enthusiasm level in writing"
            ],
            "useFirstPerson": [
                "type": "boolean",
                "description": "Whether the writer uses first person (I/we)"
            ],
            "connectiveStyle": [
                "type": "string",
                "description": "How ideas are connected (causal, sequential, contrastive)"
            ],
            "aspirationalPhrases": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Phrases used to express goals and aspirations"
            ],
            "avoidPhrases": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Corporate buzzwords the writer avoids"
            ],
            "sampleExcerpts": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Verbatim excerpts showing voice (20-50 words each)"
            ]
        ],
        "required": ["enthusiasm", "useFirstPerson", "connectiveStyle"]
    ]
}
