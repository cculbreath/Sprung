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
    private let reasoningStreamManager: ReasoningStreamState
    private var activeStreamingHandle: LLMStreamingHandle?

    private func getModelId() throws -> String {
        try ModelConfigResolver.resolve(key: "voiceProfileModelId", operation: "Voice Profile Generation")
    }

    init(llmFacade: LLMFacade?, reasoningStreamManager: ReasoningStreamState) {
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

    /// Store the extracted voice profile everywhere it is consumed:
    /// - guidance store ("objective" row) for generation guidance and the
    ///   document-analysis voice anchor
    /// - CoverRefStore `.voicePrimer` entry for cover letters, the revision
    ///   workspace, and the writing-samples browser's Voice Primers tab
    /// Both writes upsert — re-running extraction replaces the profile
    /// instead of stacking duplicates.
    func storeVoiceProfile(
        _ profile: VoiceProfile,
        in guidanceStore: InferenceGuidanceStore,
        coverRefStore: CoverRefStore
    ) {
        let attachments = GuidanceAttachments(voiceProfile: profile)

        var promptLines = ["Voice profile for content generation:"]
        promptLines += profile.characteristicPairs.map { "- \($0.label): \($0.value)" }
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

        upsertVoicePrimerRef(profile, summary: prompt, in: coverRefStore)
    }

    /// Upsert the single `.voicePrimer` CoverRef carrying the encoded profile.
    private func upsertVoicePrimerRef(
        _ profile: VoiceProfile,
        summary: String,
        in coverRefStore: CoverRefStore
    ) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(profile),
              let json = String(data: data, encoding: .utf8) else {
            Logger.error("🎤 Failed to encode voice profile for CoverRef storage", category: .ai)
            return
        }

        if let existing = coverRefStore.storedCoverRefs.first(where: { $0.type == .voicePrimer }) {
            existing.content = summary
            existing.voicePrimerJSON = json
            coverRefStore.saveContext()
            Logger.info("🎤 Voice primer CoverRef updated", category: .ai)
        } else {
            let ref = CoverRef(
                name: "Voice Profile",
                content: summary,
                enabledByDefault: true,
                type: .voicePrimer,
                voicePrimerJSON: json
            )
            _ = coverRefStore.addCoverRef(ref)
            Logger.info("🎤 Voice primer CoverRef created", category: .ai)
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
                "description": "Verbatim excerpts showing voice (20-50 words each), chosen to demonstrate the register modulation pattern — e.g. one formal Latinate passage and one plain Anglo-Saxon punchline"
            ],
            "vocabularyRegister": [
                "type": "string",
                "description": "Dominant lexical register mix: plain Anglo-Saxon/Germanic words (get, build, work), formal Latinate vocabulary (obtain, construct, collaborate), and Greek-derived technical terms (analyze, synthesize, methodology). Characterize the blend, e.g. 'Anglo-Saxon core with Latinate terms reserved for technical claims'"
            ],
            "registerModulation": [
                "type": "string",
                "description": "When and how the author shifts between vocabulary registers — e.g. drops to plain Anglo-Saxon for emphasis or conclusions, rises to Latinate for formal framing, deploys Greek-derived terminology only inside technical passages. Cite the pattern, not just the mix"
            ],
            "voiceSummary": [
                "type": "string",
                "description": "A stylist's portrait (150-300 words): what makes this voice immediately recognizable, what it would take for another writer to convincingly imitate it, and what would instantly give an impostor away. Write it as an impersonation brief, not a list of adjectives"
            ],
            "sentenceRhythm": [
                "type": "string",
                "description": "Sentence-level mechanics: typical length and variation, clause architecture (appositives, em-dash elaborations, parentheticals), punctuation habits, and cadence patterns — e.g. 'long multi-clause builds resolved by an abrupt short declarative'"
            ],
            "rhetoricalMoves": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Named recurring rhetorical moves, each with a brief verbatim mini-example — e.g. 'anaphora for conviction (\"I love… I know… I learned…\")', 'concrete anecdote escalated into thesis', 'enumerate three capabilities then synthesize into identity claim'"
            ],
            "openingStyle": [
                "type": "string",
                "description": "How pieces open: the characteristic first-paragraph move (direct declaration, scene-setting anecdote, thesis-first, etc.) with a verbatim fragment as evidence"
            ],
            "closingStyle": [
                "type": "string",
                "description": "How pieces close: the characteristic final move (return to opening image, plain-register conviction statement, forward-looking commitment, etc.) with a verbatim fragment as evidence"
            ]
        ],
        "required": ["enthusiasm", "useFirstPerson", "connectiveStyle", "vocabularyRegister", "registerModulation", "voiceSummary", "sentenceRhythm", "rhetoricalMoves"],
        "additionalProperties": false
    ]
}
