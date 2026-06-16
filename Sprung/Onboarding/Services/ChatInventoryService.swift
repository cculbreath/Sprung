//
//  ChatInventoryService.swift
//  Sprung
//
//  Service for extracting skills and narrative cards from chat transcript.
//  Creates a "chat transcript" artifact that participates in knowledge merge.
//  Runs two structured Anthropic calls that share a cached system + transcript
//  prefix: the first (awaited) call warms the cache, the second reads it.
//

import Foundation
import SwiftyJSON
import SwiftOpenAI

/// Service that extracts skills and narrative cards from the chat transcript
/// and creates an artifact for inclusion in the knowledge merge.
actor ChatInventoryService {
    private let llmFacade: LLMFacade
    private let conversationLog: ConversationLog
    private let artifactRepository: ArtifactRepository
    private let eventBus: EventBus

    init(
        llmFacade: LLMFacade,
        conversationLog: ConversationLog,
        artifactRepository: ArtifactRepository,
        eventBus: EventBus
    ) {
        self.llmFacade = llmFacade
        self.conversationLog = conversationLog
        self.artifactRepository = artifactRepository
        self.eventBus = eventBus
        Logger.info("💬 ChatInventoryService initialized", category: .ai)
    }

    /// Extract skills and narrative cards from chat and create artifact
    /// - Returns: The created artifact ID, or nil if no relevant facts found
    func extractAndCreateArtifact() async throws -> String? {
        // Get all messages from ConversationLog (source of truth)
        let messages = await conversationLog.getMessagesForUI()

        // Filter to user messages only (these contain the facts)
        let userMessages = messages.filter { $0.role == .user && !$0.isSystemGenerated }

        guard !userMessages.isEmpty else {
            Logger.info("💬 No user messages to extract knowledge from", category: .ai)
            return nil
        }

        // Format transcript for LLM
        let transcript = formatTranscript(messages: messages)

        Logger.info("💬 Extracting chat knowledge from \(userMessages.count) user messages", category: .ai)

        let modelId = try ModelConfigResolver.resolve(key: "onboardingCardMergeModelId", operation: "Chat Inventory Processing")

        // Shared cached prefix for both extraction calls: system block +
        // transcript block each carry a breakpoint (2 of 4 max). The skills
        // call runs first and warms the cache; the cards call reuses it.
        let systemBlocks = [AnthropicSystemBlock(text: Self.systemPrompt, cacheControl: .ephemeral)]
        let transcriptBlock = AnthropicContentBlock.text(AnthropicTextBlock(
            text: "CONVERSATION TRANSCRIPT:\n---\n\(transcript)\n---",
            cacheControl: .ephemeral
        ))

        // Extract skills
        let skills: [Skill]
        do {
            let response: ChatSkillsResponse = try await llmFacade.executeStructuredWithAnthropicBlocks(
                systemContent: systemBlocks,
                userBlocks: [transcriptBlock, .text(AnthropicTextBlock(text: Self.skillsInstructions))],
                modelId: modelId,
                responseType: ChatSkillsResponse.self,
                schema: SkillBankPrompts.jsonSchema,
                maxTokens: 16384
            )
            skills = response.skills
        } catch let error as ModelConfigurationError {
            throw error
        } catch {
            Logger.warning("⚠️ Chat skills extraction failed: \(error.localizedDescription)", category: .ai)
            return nil
        }

        // Extract narrative cards (reads the cache the skills call just wrote)
        let narrativeCards: [KnowledgeCard]
        do {
            let response: ChatCardsResponse = try await llmFacade.executeStructuredWithAnthropicBlocks(
                systemContent: systemBlocks,
                userBlocks: [transcriptBlock, .text(AnthropicTextBlock(text: Self.narrativeCardsInstructions))],
                modelId: modelId,
                responseType: ChatCardsResponse.self,
                schema: Self.narrativeCardsSchema,
                maxTokens: 16384
            )
            narrativeCards = response.cards
        } catch {
            // Don't discard skills the first call already produced — degrade to
            // a skills-only artifact (the both-empty guard below still applies).
            Logger.warning("⚠️ Chat narrative cards extraction failed: \(error.localizedDescription) — keeping extracted skills", category: .ai)
            narrativeCards = []
        }

        // Check if anything was extracted
        guard !skills.isEmpty || !narrativeCards.isEmpty else {
            Logger.info("💬 No knowledge extracted from chat - no relevant facts found", category: .ai)
            return nil
        }

        Logger.info("💬 Extracted \(skills.count) skills and \(narrativeCards.count) narrative cards from chat", category: .ai)

        // Create artifact record
        let artifactId = "chat-transcript-\(UUID().uuidString.prefix(8))"

        // Encode to JSON strings
        // Note: Skill/KnowledgeCard models have explicit CodingKeys for snake_case - no conversion needed
        let encoder = JSONEncoder()
        let skillsJSON = skills.isEmpty ? nil : String(data: try encoder.encode(skills), encoding: .utf8)
        let narrativeCardsJSON = narrativeCards.isEmpty ? nil : String(data: try encoder.encode(narrativeCards), encoding: .utf8)

        // Build artifact record
        var artifactRecord = JSON()
        artifactRecord["id"].string = artifactId
        artifactRecord["filename"].string = "Interview Conversation"
        artifactRecord["sourceType"].string = "chat"
        artifactRecord["uploadTime"].string = ISO8601DateFormatter().string(from: Date())
        artifactRecord["skills"].string = skillsJSON
        artifactRecord["narrativeCards"].string = narrativeCardsJSON

        // Store in artifact repository
        await artifactRepository.addArtifactRecord(artifactRecord)

        Logger.info("✅ Chat transcript artifact created: \(artifactId) with \(skills.count) skills and \(narrativeCards.count) cards", category: .ai)

        return artifactId
    }

    // MARK: - Private

    private func formatTranscript(messages: [OnboardingMessage]) -> String {
        var lines: [String] = []
        for message in messages {
            let role = message.role == .user ? "User" : "Assistant"
            // Skip system-generated messages and very short messages
            if message.isSystemGenerated { continue }
            if message.text.count < 10 { continue }
            lines.append("[\(role)]: \(message.text)")
        }
        return lines.joined(separator: "\n\n")
    }

    // MARK: - Prompts

    private static let systemPrompt = """
        You are a career-knowledge extraction assistant. You analyze interview \
        conversation transcripts in which a user discusses their career, \
        achievements, skills, and experience, and you extract structured \
        knowledge (skill inventories and narrative knowledge cards) exactly \
        matching the requested JSON schema.
        """

    private static let skillsInstructions = """
        Extract a COMPREHENSIVE skill inventory from the conversation transcript above.

        This is a BANK of all possible skills — completeness matters more than selectivity. \
        When in doubt, INCLUDE the skill.

        Extract ALL skills, including:
        - Technical skills and technologies mentioned explicitly
        - Skills IMPLIED by the work described (e.g., if they managed a team, extract \
          "team management", "performance reviews", "hiring", "mentoring")
        - Domain knowledge and expertise areas
        - Tools, frameworks, and methodologies
        - Soft skills demonstrated through concrete examples
        - Research methods, writing skills, regulatory knowledge if applicable
        - Adjacent skills implied by primary ones (e.g., "Python" implies "pip", \
          "virtual environments", "debugging")

        For each skill:
        - Set `implied` to false when the skill was explicitly demonstrated or discussed, \
          and true when it is only inferred from context. Cap implied-skill evidence \
          strength at "supporting" or "mention" — never "primary".
        - Provide evidence with document_id "chat", a location like "conversation", a brief \
          context note, and a strength (primary, supporting, mention).
        - List ATS variants of the skill name inside ats_variants — variants are NEVER \
          separate skill entries.

        If no clear skills are mentioned, return an empty skills array.
        """

    private static let narrativeCardsInstructions = """
        Extract narrative knowledge cards from the conversation transcript above.

        Focus on:
        - Employment experiences and roles discussed
        - Projects described with enough detail for a narrative
        - Achievements and accomplishments mentioned
        - Educational experiences if discussed in depth

        For each card, write a narrative that captures:
        - The CONTEXT: What was the situation and the applicant's role?
        - The APPROACH: What did they do and what reasoning drove their decisions?
        - The SIGNIFICANCE: What was accomplished, discovered, or advanced?

        IMPORTANT:
        - Only create cards for experiences with enough detail for a meaningful narrative
        - Use "chat" as the document_id in evidence_anchors
        - If no substantial career narratives are shared, return an empty cards array
        - Focus on accomplishments, expertise, and what was built/discovered — omit
          negative content like performance criticisms, failures, or self-deprecation
        """

    // MARK: - Schemas

    /// JSON Schema for narrative cards extracted from chat. Keys match the
    /// KnowledgeCard Codable wire format (snake_case).
    static let narrativeCardsSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "cards": [
                "type": "array",
                "description": "Narrative knowledge cards extracted from the conversation",
                "items": [
                    "type": "object",
                    "properties": [
                        "id": [
                            "type": "string",
                            "description": "Unique identifier (UUID format)"
                        ],
                        "card_type": [
                            "type": "string",
                            "enum": ["employment", "project", "achievement", "education"],
                            "description": "Type of knowledge card"
                        ],
                        "title": [
                            "type": "string",
                            "description": "Specific, descriptive title for the card"
                        ],
                        "narrative": [
                            "type": "string",
                            "description": "Narrative capturing context, approach, and significance in the user's voice"
                        ],
                        "organization": [
                            "type": "string",
                            "description": "Company, institution, or organization"
                        ],
                        "date_range": [
                            "type": "string",
                            "description": "Time period if applicable"
                        ],
                        "evidence_anchors": [
                            "type": "array",
                            "description": "Links back to the conversation",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "document_id": [
                                        "type": "string",
                                        "description": "Always \"chat\" for conversation-sourced cards"
                                    ],
                                    "location": [
                                        "type": "string",
                                        "description": "Where in the conversation this was discussed"
                                    ],
                                    "verbatim_excerpt": [
                                        "type": "string",
                                        "description": "Short verbatim quote from the user (20-50 words)"
                                    ]
                                ],
                                "required": ["document_id", "location"],
                                "additionalProperties": false
                            ]
                        ],
                        "extractable": [
                            "type": "object",
                            "description": "Metadata for job matching",
                            "properties": [
                                "domains": [
                                    "type": "array",
                                    "items": ["type": "string"],
                                    "description": "Fields of expertise"
                                ],
                                "scale": [
                                    "type": "array",
                                    "items": ["type": "string"],
                                    "description": "Quantified elements (numbers, metrics, scope)"
                                ],
                                "keywords": [
                                    "type": "array",
                                    "items": ["type": "string"],
                                    "description": "High-level terms for job matching"
                                ]
                            ],
                            "additionalProperties": false
                        ]
                    ],
                    "required": ["id", "card_type", "title", "narrative", "evidence_anchors"],
                    "additionalProperties": false
                ]
            ]
        ],
        "required": ["cards"],
        "additionalProperties": false
    ]
}

// MARK: - Response Wrappers

/// Wrapper for the skills extraction response (schema: SkillBankPrompts.jsonSchema)
private struct ChatSkillsResponse: Codable {
    let skills: [Skill]
}

/// Wrapper for the narrative cards extraction response
private struct ChatCardsResponse: Codable {
    let cards: [KnowledgeCard]
}
