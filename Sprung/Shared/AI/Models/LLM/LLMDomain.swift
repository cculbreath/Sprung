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
struct LLMStreamChunkDTO: Sendable {
    var content: String?
    var reasoning: String?
    var event: LLMStreamEvent? = nil
    var isFinished: Bool
}
enum LLMStreamEvent: Sendable {
    case tool(LLMToolStreamEvent)
    case status(message: String, isComplete: Bool)
}
struct LLMToolStreamEvent: Sendable {
    var callId: String
    var status: String?
    var payload: String?
    var appendsPayload: Bool
    var isComplete: Bool
    var toolName: String?
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
