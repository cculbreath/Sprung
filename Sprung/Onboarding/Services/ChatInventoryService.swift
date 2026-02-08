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
    private let conversationLog: ConversationLog
    private let artifactRepository: ArtifactRepository
    private let eventBus: EventCoordinator

    init(
        llmFacade: LLMFacade,
        conversationLog: ConversationLog,
        artifactRepository: ArtifactRepository,
        eventBus: EventCoordinator
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

        // Call LLM with structured output for skills
        guard let modelId = UserDefaults.standard.string(forKey: "onboardingCardMergeModelId"), !modelId.isEmpty else {
            throw ModelConfigurationError.modelNotConfigured(
                settingKey: "onboardingCardMergeModelId",
                operationName: "Chat Inventory Processing"
            )
        }

        // Extract skills
        let skills: [Skill]
        do {
            skills = try await llmFacade.executeStructuredWithSchema(
                prompt: buildSkillsExtractionPrompt(transcript: transcript),
                modelId: modelId,
                as: [Skill].self,
                schema: Self.skillsSchema,
                schemaName: "chat_skills",
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
                schemaName: "chat_narrativeCards",
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

    private func buildSkillsExtractionPrompt(transcript: String) -> String {
        """
        You are extracting a COMPREHENSIVE skill inventory from an interview conversation. \
        The user has been discussing their career, achievements, skills, and experience.

        This is a BANK of all possible skills — completeness matters more than selectivity. \
        When in doubt, INCLUDE the skill at a lower proficiency level.

        Review the conversation below and extract ALL skills, including:
        - Technical skills and technologies mentioned explicitly
        - Skills IMPLIED by the work described (e.g., if they managed a team, extract \
          "team management", "performance reviews", "hiring", "mentoring")
        - Domain knowledge and expertise areas
        - Tools, frameworks, and methodologies
        - Soft skills demonstrated through concrete examples
        - Research methods, writing skills, regulatory knowledge if applicable
        - Adjacent skills implied by primary ones (e.g., "Python" implies "pip", \
          "virtual environments", "debugging")

        For each skill, assess:
        - The proficiency level based on how they discuss it (expert, advanced, intermediate, beginner)
        - Years of experience if mentioned
        - Evidence strength (strong, moderate, weak) based on specificity of claims

        IMPORTANT:
        - Extract both explicit AND implied skills
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
        - The CONTEXT: What was the situation and the applicant's role?
        - The APPROACH: What did they do and what reasoning drove their decisions?
        - The SIGNIFICANCE: What was accomplished, discovered, or advanced?

        IMPORTANT:
        - Only create cards for experiences with enough detail for a meaningful narrative
        - Use "chat" as the source document ID
        - Set evidence strength to "moderate" since chat is supplemental to documents
        - If no substantial career narratives are shared, return an empty array
        - Focus on accomplishments, expertise, and what was built/discovered — omit
          negative content like performance criticisms, failures, or self-deprecation

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
                "sourceDocumentId": JSONSchema(type: .string),
                "quoteOrReference": JSONSchema(type: .string),
                "strength": JSONSchema(type: .string, enum: ["strong", "moderate", "weak"])
            ],
            required: ["sourceDocumentId", "strength"]
        )

        let skillSchema = JSONSchema(
            type: .object,
            properties: [
                "name": JSONSchema(type: .string, description: "The skill name"),
                "category": JSONSchema(type: .string, enum: ["technical", "softSkill", "domain", "tool", "methodology"]),
                "proficiency": JSONSchema(type: .string, enum: ["expert", "advanced", "intermediate", "beginner"]),
                "yearsExperience": JSONSchema(type: .integer),
                "atsVariants": JSONSchema(type: .array, items: JSONSchema(type: .string)),
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
                "sourceDocumentId": JSONSchema(type: .string),
                "quoteOrReference": JSONSchema(type: .string),
                "strength": JSONSchema(type: .string, enum: ["strong", "moderate", "weak"])
            ],
            required: ["sourceDocumentId", "strength"]
        )

        let cardSchema = JSONSchema(
            type: .object,
            properties: [
                "id": JSONSchema(type: .string),
                "cardType": JSONSchema(type: .string, enum: ["employment", "project", "achievement", "education", "volunteer", "certification", "publication", "award"]),
                "title": JSONSchema(type: .string),
                "organization": JSONSchema(type: .string),
                "timePeriod": JSONSchema(type: .string),
                "whySection": JSONSchema(type: .string, description: "Context: the situation and the applicant's role"),
                "journeySection": JSONSchema(type: .string, description: "Approach: what they did and what reasoning drove decisions"),
                "lessonsSection": JSONSchema(type: .string, description: "Significance: what was accomplished, discovered, or advanced"),
                "technologies": JSONSchema(type: .array, items: JSONSchema(type: .string)),
                "evidence": JSONSchema(type: .array, items: evidenceAnchorSchema),
                "extractableMetadata": JSONSchema(
                    type: .object,
                    properties: [
                        "metrics": JSONSchema(type: .array, items: JSONSchema(type: .string)),
                        "keyAchievements": JSONSchema(type: .array, items: JSONSchema(type: .string)),
                        "collaborations": JSONSchema(type: .array, items: JSONSchema(type: .string))
                    ]
                )
            ],
            required: ["id", "cardType", "title", "whySection", "journeySection", "lessonsSection"]
        )

        return JSONSchema(type: .array, items: cardSchema)
    }()
}
