//
//  ChatInventoryService.swift
//  Sprung
//
//  Service for extracting card inventory from chat transcript.
//  Creates a "chat transcript" artifact that participates in card merge.
//

import Foundation
import SwiftyJSON
import SwiftOpenAI

/// Service that extracts a card inventory from the chat transcript
/// and creates an artifact for inclusion in the card merge.
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

    /// Extract card inventory from chat and create artifact
    /// - Returns: The created artifact ID, or nil if no relevant facts found
    func extractAndCreateArtifact() async throws -> String? {
        // Get all messages from chat
        let messages = await chatTranscriptStore.getAllMessages()

        // Filter to user messages only (these contain the facts)
        let userMessages = messages.filter { $0.role == .user && !$0.isSystemGenerated }

        guard !userMessages.isEmpty else {
            Logger.info("💬 No user messages to extract inventory from", category: .ai)
            return nil
        }

        // Format transcript for LLM
        let transcript = formatTranscript(messages: messages)

        Logger.info("💬 Extracting chat inventory from \(userMessages.count) user messages", category: .ai)

        // Call LLM with structured output
        let modelId = UserDefaults.standard.string(forKey: "onboardingCardMergeModelId") ?? "openai/gpt-4o"

        let inventory: DocumentInventory
        do {
            inventory = try await llmFacade.executeStructuredWithSchema(
                prompt: buildExtractionPrompt(transcript: transcript),
                modelId: modelId,
                as: DocumentInventory.self,
                schema: Self.inventorySchema,
                schemaName: "chat_card_inventory",
                temperature: 0.2,
                backend: .openRouter
            )
        } catch {
            Logger.error("❌ Chat inventory extraction failed: \(error.localizedDescription)", category: .ai)
            throw error
        }

        // Check if any cards were extracted
        guard !inventory.proposedCards.isEmpty else {
            Logger.info("💬 No cards extracted from chat - no relevant facts found", category: .ai)
            return nil
        }

        Logger.info("💬 Extracted \(inventory.proposedCards.count) cards from chat", category: .ai)

        // Create artifact record
        let artifactId = "chat-transcript-\(UUID().uuidString.prefix(8))"

        // Encode inventory to JSON string (same format as document artifacts)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let inventoryData = try encoder.encode(inventory)
        let inventoryString = String(data: inventoryData, encoding: .utf8) ?? "{}"

        // Build artifact record
        var artifactRecord = JSON()
        artifactRecord["id"].string = artifactId
        artifactRecord["filename"].string = "Interview Conversation"
        artifactRecord["source_type"].string = "chat"
        artifactRecord["upload_time"].string = ISO8601DateFormatter().string(from: Date())
        artifactRecord["card_inventory"].string = inventoryString

        // Store in artifact repository
        await artifactRepository.addArtifactRecord(artifactRecord)

        Logger.info("✅ Chat transcript artifact created: \(artifactId) with \(inventory.proposedCards.count) cards", category: .ai)

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

    private func buildExtractionPrompt(transcript: String) -> String {
        """
        You are extracting a card inventory from an interview conversation. The user has been \
        discussing their career, achievements, skills, and experience.

        Review the conversation below and extract any facts that would be useful for generating \
        resume content. Focus on:
        - Achievements and metrics mentioned verbally
        - Skills and technologies discussed
        - Career context, goals, and motivations
        - Details about roles not covered in uploaded documents
        - Projects, responsibilities, or accomplishments shared in conversation

        For each distinct topic (job role, skill area, project, etc.), create a card entry with \
        the relevant facts extracted from the conversation.

        If the user hasn't shared any career-relevant facts in the conversation, return an empty \
        cards array.

        IMPORTANT:
        - Use "chat" as evidence_locations for all facts (e.g., ["chat: user mentioned..."])
        - Set evidence_strength to "supporting" since chat is supplemental to documents
        - Only include facts explicitly stated by the user, not inferences

        CONVERSATION TRANSCRIPT:
        ---
        \(transcript)
        ---

        Extract the card inventory now.
        """
    }

    // MARK: - Schema

    /// JSON Schema for DocumentInventory (matches document extraction format)
    static let inventorySchema: JSONSchema = {
        let cardTypeSchema = JSONSchema(
            type: .string,
            enum: ["employment", "project", "skill", "achievement", "education"]
        )

        let evidenceStrengthSchema = JSONSchema(
            type: .string,
            enum: ["primary", "supporting", "mention"]
        )

        let cardSchema = JSONSchema(
            type: .object,
            properties: [
                "card_type": cardTypeSchema,
                "proposed_title": JSONSchema(type: .string, description: "Title for this card"),
                "evidence_strength": evidenceStrengthSchema,
                "evidence_locations": JSONSchema(type: .array, items: JSONSchema(type: .string)),
                "key_facts": JSONSchema(type: .array, items: JSONSchema(type: .string)),
                "technologies": JSONSchema(type: .array, items: JSONSchema(type: .string)),
                "quantified_outcomes": JSONSchema(type: .array, items: JSONSchema(type: .string)),
                "date_range": JSONSchema(type: .string),
                "cross_references": JSONSchema(type: .array, items: JSONSchema(type: .string)),
                "extraction_notes": JSONSchema(type: .string)
            ],
            required: ["card_type", "proposed_title", "evidence_strength", "evidence_locations", "key_facts"]
        )

        return JSONSchema(
            type: .object,
            properties: [
                "document_id": JSONSchema(type: .string, description: "Use 'chat-transcript'"),
                "document_type": JSONSchema(type: .string, description: "Use 'conversation'"),
                "cards": JSONSchema(type: .array, items: cardSchema),
                "generated_at": JSONSchema(type: .string, description: "ISO8601 timestamp")
            ],
            required: ["document_id", "document_type", "cards", "generated_at"]
        )
    }()
}
