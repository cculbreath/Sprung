//
//  ChatInventoryService.swift
//  Sprung
//
//  Service for extracting skills and narrative cards from chat transcript.
//  Creates a "chat transcript" artifact that participates in knowledge merge.
//

import Foundation
import SwiftyJSON
import SwiftOpenAI

/// Service that extracts skills and narrative cards from the chat transcript
/// and creates an artifact for inclusion in the knowledge merge.
actor ChatInventoryService {
    private let llmFacade: LLMFacade
    private let chatTranscriptStore: ChatTranscriptStore
    private let artifactRepository: ArtifactRepository
    private let eventBus: EventCoordinator

    init(
        llmFacade: LLMFacade,
        chatTranscriptStore: ChatTranscriptStore,
        artifactRepository: ArtifactRepository,
        eventBus: EventCoordinator
    ) {
        self.llmFacade = llmFacade
        self.chatTranscriptStore = chatTranscriptStore
        self.artifactRepository = artifactRepository
        self.eventBus = eventBus
        Logger.info("💬 ChatInventoryService initialized", category: .ai)
    }

    /// Extract skills and narrative cards from chat and create artifact
    /// - Returns: The created artifact ID, or nil if no relevant facts found
    func extractAndCreateArtifact() async throws -> String? {
        // Get all messages from chat
        let messages = await chatTranscriptStore.getAllMessages()

        // Filter to user messages only (these contain the facts)
        let userMessages = messages.filter { $0.role == .user && !$0.isSystemGenerated }

        guard !userMessages.isEmpty else {
            Logger.info("💬 No user messages to extract knowledge from", category: .ai)
            return nil
        }

        // Format transcript for LLM
        let transcript = formatTranscript(messages: messages)

        Logger.info("💬 Extracting chat knowledge from \(userMessages.count) user messages", category: .ai)

        // Call LLM with structured output for skills
        let modelId = UserDefaults.standard.string(forKey: "onboardingCardMergeModelId") ?? "openai/gpt-4o"

        // Extract skills
        let skills: [Skill]
        do {
            skills = try await llmFacade.executeStructuredWithSchema(
                prompt: buildSkillsExtractionPrompt(transcript: transcript),
                modelId: modelId,
                as: [Skill].self,
                schema: Self.skillsSchema,
                schemaName: "chat_skills",
                temperature: 0.2,
                backend: .openRouter
            )
        } catch {
            Logger.warning("⚠️ Chat skills extraction failed: \(error.localizedDescription)", category: .ai)
            return nil
        }

        // Extract narrative cards
        let narrativeCards: [KnowledgeCard]
        do {
            narrativeCards = try await llmFacade.executeStructuredWithSchema(
                prompt: buildNarrativeCardsExtractionPrompt(transcript: transcript),
                modelId: modelId,
                as: [KnowledgeCard].self,
                schema: Self.narrativeCardsSchema,
                schemaName: "chat_narrative_cards",
                temperature: 0.2,
                backend: .openRouter
            )
        } catch {
            Logger.warning("⚠️ Chat narrative cards extraction failed: \(error.localizedDescription)", category: .ai)
            return nil
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
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let skillsJSON = skills.isEmpty ? nil : String(data: try encoder.encode(skills), encoding: .utf8)
        let narrativeCardsJSON = narrativeCards.isEmpty ? nil : String(data: try encoder.encode(narrativeCards), encoding: .utf8)

        // Build artifact record
        var artifactRecord = JSON()
        artifactRecord["id"].string = artifactId
        artifactRecord["filename"].string = "Interview Conversation"
        artifactRecord["source_type"].string = "chat"
        artifactRecord["upload_time"].string = ISO8601DateFormatter().string(from: Date())
        artifactRecord["skills"].string = skillsJSON
        artifactRecord["narrative_cards"].string = narrativeCardsJSON

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

    private func buildSkillsExtractionPrompt(transcript: String) -> String {
        """
        You are extracting skills from an interview conversation. The user has been \
        discussing their career, achievements, skills, and experience.

        Review the conversation below and extract any skills that the user mentions. Focus on:
        - Technical skills and technologies mentioned
        - Soft skills demonstrated through examples
        - Domain knowledge and expertise areas
        - Tools, frameworks, and methodologies

        For each skill, assess:
        - The proficiency level based on how they discuss it (expert, advanced, intermediate, beginner)
        - Years of experience if mentioned
        - Evidence strength (strong, moderate, weak) based on specificity of claims

        IMPORTANT:
        - Only include skills explicitly stated or clearly demonstrated by the user
        - Use "chat" as the source document ID
        - If no clear skills are mentioned, return an empty array

        CONVERSATION TRANSCRIPT:
        ---
        \(transcript)
        ---

        Extract the skills now as a JSON array.
        """
    }

    private func buildNarrativeCardsExtractionPrompt(transcript: String) -> String {
        """
        You are extracting narrative knowledge cards from an interview conversation. The user has been \
        discussing their career, achievements, skills, and experience.

        Review the conversation below and extract any career narratives that would make good \
        knowledge cards. Focus on:
        - Employment experiences and roles discussed
        - Projects described with enough detail for a narrative
        - Achievements and accomplishments mentioned
        - Educational experiences if discussed in depth

        For each card, capture:
        - The WHY: Context and motivation for this experience
        - The JOURNEY: What happened, challenges faced, actions taken
        - The LESSONS: Outcomes, learnings, and growth

        IMPORTANT:
        - Only create cards for experiences with enough detail for a meaningful narrative
        - Use "chat" as the source document ID
        - Set evidence strength to "moderate" since chat is supplemental to documents
        - If no substantial career narratives are shared, return an empty array

        CONVERSATION TRANSCRIPT:
        ---
        \(transcript)
        ---

        Extract the narrative cards now as a JSON array.
        """
    }

    // MARK: - Schemas

    /// JSON Schema for skills array
    static let skillsSchema: JSONSchema = {
        let evidenceAnchorSchema = JSONSchema(
            type: .object,
            properties: [
                "source_document_id": JSONSchema(type: .string),
                "quote_or_reference": JSONSchema(type: .string),
                "strength": JSONSchema(type: .string, enum: ["strong", "moderate", "weak"])
            ],
            required: ["source_document_id", "strength"]
        )

        let skillSchema = JSONSchema(
            type: .object,
            properties: [
                "name": JSONSchema(type: .string, description: "The skill name"),
                "category": JSONSchema(type: .string, enum: ["technical", "soft_skill", "domain", "tool", "methodology"]),
                "proficiency": JSONSchema(type: .string, enum: ["expert", "advanced", "intermediate", "beginner"]),
                "years_experience": JSONSchema(type: .integer),
                "ats_variants": JSONSchema(type: .array, items: JSONSchema(type: .string)),
                "evidence": JSONSchema(type: .array, items: evidenceAnchorSchema),
                "context": JSONSchema(type: .string)
            ],
            required: ["name", "category", "proficiency"]
        )

        return JSONSchema(type: .array, items: skillSchema)
    }()

    /// JSON Schema for narrative cards array
    static let narrativeCardsSchema: JSONSchema = {
        let evidenceAnchorSchema = JSONSchema(
            type: .object,
            properties: [
                "source_document_id": JSONSchema(type: .string),
                "quote_or_reference": JSONSchema(type: .string),
                "strength": JSONSchema(type: .string, enum: ["strong", "moderate", "weak"])
            ],
            required: ["source_document_id", "strength"]
        )

        let cardSchema = JSONSchema(
            type: .object,
            properties: [
                "id": JSONSchema(type: .string),
                "card_type": JSONSchema(type: .string, enum: ["employment", "project", "achievement", "education", "volunteer", "certification", "publication", "award"]),
                "title": JSONSchema(type: .string),
                "organization": JSONSchema(type: .string),
                "time_period": JSONSchema(type: .string),
                "why_section": JSONSchema(type: .string, description: "Context and motivation"),
                "journey_section": JSONSchema(type: .string, description: "What happened, challenges, actions"),
                "lessons_section": JSONSchema(type: .string, description: "Outcomes and learnings"),
                "technologies": JSONSchema(type: .array, items: JSONSchema(type: .string)),
                "evidence": JSONSchema(type: .array, items: evidenceAnchorSchema),
                "extractable_metadata": JSONSchema(
                    type: .object,
                    properties: [
                        "metrics": JSONSchema(type: .array, items: JSONSchema(type: .string)),
                        "key_achievements": JSONSchema(type: .array, items: JSONSchema(type: .string)),
                        "collaborations": JSONSchema(type: .array, items: JSONSchema(type: .string))
                    ]
                )
            ],
            required: ["id", "card_type", "title", "why_section", "journey_section", "lessons_section"]
        )

        return JSONSchema(type: .array, items: cardSchema)
    }()
}
