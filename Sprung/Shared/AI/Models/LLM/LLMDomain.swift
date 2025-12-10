//
//  LLMDomain.swift
//  Sprung
//
//  Defines vendor-neutral DTOs and helpers for interacting with large language
//  models. SwiftOpenAI-specific types are confined to adapter implementations
//  that translate between these structures and provider SDKs.
//
import Foundation
// MARK: - Roles & Attachments
enum LLMRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}
struct LLMAttachment: Codable, Sendable {
    var data: Data
    var mimeType: String
}
// MARK: - Messages
struct LLMMessageDTO: Codable, Sendable, Identifiable {
    var id: UUID
    var role: LLMRole
    var text: String?
    var attachments: [LLMAttachment]
    var createdAt: Date?
    init(id: UUID = UUID(), role: LLMRole, text: String?, attachments: [LLMAttachment] = [], createdAt: Date? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.attachments = attachments
        self.createdAt = createdAt
    }
}
/// Represents a single reasoning detail extracted from streaming responses.
/// Matches OpenRouter's reasoning_details structure.
struct LLMReasoningDetailDTO: Sendable {
    /// Type of reasoning: "reasoning.text", "reasoning.summary", or "reasoning.encrypted"
    var type: String?
    /// Raw reasoning text (for "reasoning.text" type)
    var text: String?
    /// High-level summary (for "reasoning.summary" type)
    var summary: String?
    /// Format identifier: "anthropic-claude-v1", "openai-responses-v1", "xai-responses-v1"
    var format: String?

    /// Extracts the displayable reasoning text from this detail.
    /// Prefers text content, falls back to summary.
    var displayText: String? {
        text ?? summary
    }
}

struct LLMStreamChunkDTO: Sendable {
    var content: String?
    /// Legacy simple reasoning string (for backwards compatibility)
    var reasoning: String?
    /// Structured reasoning details from OpenRouter's new format
    var reasoningDetails: [LLMReasoningDetailDTO]?
    var isFinished: Bool

    /// Extracts all reasoning text from this chunk, combining legacy and new formats.
    /// Prioritizes structured reasoning_details, falls back to legacy reasoning string.
    var allReasoningText: String? {
        // First try structured reasoning details
        if let details = reasoningDetails, !details.isEmpty {
            let texts = details.compactMap { $0.displayText }
            if !texts.isEmpty {
                return texts.joined()
            }
        }
        // Fall back to legacy simple string
        return reasoning
    }
}
// MARK: - Responses
struct LLMResponseChoiceDTO: Codable, Sendable {
    var message: LLMMessageDTO?
}
struct LLMResponseDTO: Codable, Sendable {
    var choices: [LLMResponseChoiceDTO]
}
// MARK: - Convenience Helpers
extension LLMMessageDTO {
    static func text(_ text: String, role: LLMRole) -> LLMMessageDTO {
        LLMMessageDTO(role: role, text: text, attachments: [])
    }
}
