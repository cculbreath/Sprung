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
            throw VoiceProfileError.noWritingSamples
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

        let maxAttempts = 3
        for attempt in 1...maxAttempts {
            Logger.info("🎤 Voice profile extraction attempt \(attempt)/\(maxAttempts)", category: .ai)

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

                for try await chunk in handle.stream {
                    if let reasoningContent = chunk.allReasoningText {
                        reasoningStreamManager.reasoningText += reasoningContent
                    }
                    if let content = chunk.content {
                        fullResponse += content
                    }
                    if chunk.isFinished {
                        reasoningStreamManager.isStreaming = false
                        reasoningStreamManager.isVisible = false
                    }
                }

                activeStreamingHandle = nil

                // The parser handles fenced/embedded JSON, so feed it the full
                // response rather than a chunk-boundary-dependent slice.
                do {
                    let profile: VoiceProfile = try JSONResponseParser.parseText(fullResponse, as: VoiceProfile.self)
                    Logger.info(
                        "🎤 Extracted voice profile: \(profile.enthusiasm.displayName), first person: \(profile.useFirstPerson)",
                        category: .ai
                    )
                    return profile
                } catch {
                    // Keep the unparseable response diagnosable from the console log.
                    Logger.warning(
                        "🎤 Voice profile response failed to parse (attempt \(attempt)/\(maxAttempts), \(fullResponse.count) chars): \(fullResponse.prefix(2000))",
                        category: .ai
                    )
                    throw error
                }
            } catch let error as ModelConfigurationError {
                cleanUpAfterFailure()
                throw error
            } catch {
                cleanUpAfterFailure()
                if attempt < maxAttempts { continue }
                throw error
            }
        }

        // Unreachable: the loop either returns a profile or throws on the last attempt.
        throw VoiceProfileError.extractionFailed
    }

    private func cleanUpAfterFailure() {
        activeStreamingHandle = nil
        reasoningStreamManager.isStreaming = false
        reasoningStreamManager.isVisible = false
    }

    /// Store extracted voice profile in guidance store. Upserts the single
    /// "objective" guidance row — re-running extraction (onboarding debug
    /// button, KC browser) replaces the profile instead of stacking duplicates.
    func storeVoiceProfile(_ profile: VoiceProfile, in guidanceStore: InferenceGuidanceStore) {
        let attachments = GuidanceAttachments(voiceProfile: profile)

        var promptLines = [
            "Voice profile for content generation:",
            "- Enthusiasm: \(profile.enthusiasm.displayName)",
            "- Person: \(profile.useFirstPerson ? "First person (I built, I discovered)" : "Third person")",
            "- Connectives: \(profile.connectiveStyle)",
            "- Aspirational phrases: \(profile.aspirationalPhrases.joined(separator: ", "))",
            "- NEVER use: \(profile.avoidPhrases.joined(separator: ", "))"
        ]
        if let register = profile.vocabularyRegister, !register.isEmpty {
            promptLines.append("- Vocabulary register: \(register)")
        }
        if let modulation = profile.registerModulation, !modulation.isEmpty {
            promptLines.append("- Register modulation: \(modulation)")
        }
        promptLines.append("")
        promptLines.append("Sample excerpts preserving voice:")
        promptLines.append(profile.sampleExcerpts.map { "• \"\($0)\"" }.joined(separator: "\n"))

        let prompt = promptLines.joined(separator: "\n")

        if let existing = guidanceStore.guidance(for: "objective") {
            existing.prompt = prompt
            existing.attachmentsJSON = attachments.asJSON()
            guidanceStore.update(existing)
            Logger.info("🎤 Voice profile updated in guidance store", category: .ai)
        } else {
            let guidance = InferenceGuidance(
                nodeKey: "objective",
                displayName: "Voice Profile",
                prompt: prompt,
                attachmentsJSON: attachments.asJSON(),
                source: .auto
            )
            guidanceStore.add(guidance)
            Logger.info("🎤 Voice profile stored in guidance store", category: .ai)
        }
    }

    enum VoiceProfileError: Error, LocalizedError {
        case llmNotConfigured
        case noWritingSamples
        case extractionFailed

        var errorDescription: String? {
            switch self {
            case .llmNotConfigured:
                return "LLM facade not configured"
            case .noWritingSamples:
                return "No writing samples available for voice profile extraction"
            case .extractionFailed:
                return "Voice profile extraction failed"
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
            ],
            "vocabularyRegister": [
                "type": "string",
                "description": "Dominant lexical register mix: plain Anglo-Saxon/Germanic words (get, build, work), formal Latinate vocabulary (obtain, construct, collaborate), and Greek-derived technical terms (analyze, synthesize, methodology). Characterize the blend, e.g. 'Anglo-Saxon core with Latinate terms reserved for technical claims'"
            ],
            "registerModulation": [
                "type": "string",
                "description": "When and how the author shifts between vocabulary registers — e.g. drops to plain Anglo-Saxon for emphasis or conclusions, rises to Latinate for formal framing, deploys Greek-derived terminology only inside technical passages. Cite the pattern, not just the mix"
            ]
        ],
        "required": ["enthusiasm", "useFirstPerson", "connectiveStyle", "vocabularyRegister", "registerModulation"],
        "additionalProperties": false
    ]
}
