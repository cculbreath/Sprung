//
//  LLMDomain.swift
//  PhysCloudResume
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

// MARK: - Reasoning & Response Formatting

struct LLMReasoningConfig: Codable, Sendable {
    var effort: String?
    var excludeReasoning: Bool?
    var maxTokens: Int?
}

enum LLMResponseFormat: Sendable, Equatable {
    case jsonObject
    case jsonSchema(name: String?, schema: LLMJSONSchema)

    static func == (lhs: LLMResponseFormat, rhs: LLMResponseFormat) -> Bool {
        switch (lhs, rhs) {
        case (.jsonObject, .jsonObject):
            return true
        case let (.jsonSchema(lhsName, lhsSchema), .jsonSchema(rhsName, rhsSchema)):
            return lhsName == rhsName && lhsSchema == rhsSchema
        default:
            return false
        }
    }
}

// MARK: - JSON Schema

/// Lightweight vendor-agnostic representation of a JSON schema.
/// Stores the schema as a canonical JSON string to avoid embedding vendor types.
struct LLMJSONSchema: Sendable, Equatable, Codable {
    var json: String

    init(json: String) {
        self.json = json
    }

    init(dictionary: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys])
        self.json = String(decoding: data, as: UTF8.self)
    }
}

struct LLMStreamChunkDTO: Sendable {
    var content: String?
    var reasoning: String?
    var isFinished: Bool
    var finishReason: String?
}

// MARK: - Requests & Responses

struct LLMChatRequest: Sendable {
    var modelId: String
    var messages: [LLMMessageDTO]
    var temperature: Double?
    var stream: Bool
    var responseFormat: LLMResponseFormat?
    var reasoning: LLMReasoningConfig?
}

struct LLMUsageDTO: Codable, Sendable {
    var promptTokens: Int
    var completionTokens: Int
    var totalTokens: Int
}

struct LLMResponseChoiceDTO: Codable, Sendable {
    var index: Int
    var message: LLMMessageDTO?
    var finishReason: String?
}

struct LLMResponseDTO: Codable, Sendable {
    var id: String?
    var model: String?
    var created: Date?
    var choices: [LLMResponseChoiceDTO]
    var usage: LLMUsageDTO?
}

// MARK: - Convenience Helpers

extension LLMMessageDTO {
    static func text(_ text: String, role: LLMRole) -> LLMMessageDTO {
        LLMMessageDTO(role: role, text: text, attachments: [])
    }

    static func textWithImages(_ text: String, role: LLMRole, attachments: [LLMAttachment]) -> LLMMessageDTO {
        LLMMessageDTO(role: role, text: text, attachments: attachments)
    }
}

extension LLMChatRequest {
    static func make(
        modelId: String,
        messages: [LLMMessageDTO],
        temperature: Double? = nil,
        stream: Bool = false,
        responseFormat: LLMResponseFormat? = nil,
        reasoning: LLMReasoningConfig? = nil
    ) -> LLMChatRequest {
        LLMChatRequest(
            modelId: modelId,
            messages: messages,
            temperature: temperature,
            stream: stream,
            responseFormat: responseFormat,
            reasoning: reasoning
        )
    }
}
