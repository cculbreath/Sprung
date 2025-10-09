//
//  ConversationModels.swift
//  PhysCloudResume
//
//  SwiftData persistence for LLM conversations using domain DTOs.
//

import SwiftData
import Foundation

@Model
class ConversationContext {
    var id: UUID
    var objectId: UUID
    var objectType: String
    var lastUpdated: Date

    @Relationship(deleteRule: .cascade, inverse: \ConversationMessage.context)
    var messages: [ConversationMessage] = []

    init(
        conversationId: UUID,
        objectId: UUID? = nil,
        objectType: ConversationType = .general
    ) {
        self.id = conversationId
        self.objectId = objectId ?? conversationId
        self.objectType = objectType.rawValue
        self.lastUpdated = Date()
    }
}

@Model
class ConversationMessage {
    var id: UUID
    var role: String
    var content: String
    var imageData: String?
    var timestamp: Date

    @Relationship var context: ConversationContext?

    init(role: LLMRole, content: String, imageData: String? = nil) {
        self.id = UUID()
        self.role = role.rawValue
        self.content = content
        self.imageData = imageData
        self.timestamp = Date()
    }
}

enum ConversationType: String, CaseIterable {
    case general
    case resume
    case coverLetter

    init(rawValue: String, fallback: ConversationType) {
        self = ConversationType(rawValue: rawValue) ?? fallback
    }
}

extension ConversationMessage {
    var dto: LLMMessageDTO {
        var attachments: [LLMAttachment] = []
        if let imageData,
           let data = Data(base64Encoded: imageData) {
            attachments.append(LLMAttachment(data: data, mimeType: "image/png"))
        }
        let roleEnum = LLMRole(rawValue: role) ?? .assistant
        return LLMMessageDTO(
            id: id,
            role: roleEnum,
            text: content.isEmpty ? nil : content,
            attachments: attachments,
            createdAt: timestamp
        )
    }

    func apply(dto: LLMMessageDTO) {
        id = dto.id
        role = dto.role.rawValue
        content = dto.text ?? ""
        imageData = dto.attachments.first?.data.base64EncodedString()
        timestamp = dto.createdAt ?? Date()
    }

    static func fromDTO(_ dto: LLMMessageDTO) -> ConversationMessage {
        let message = ConversationMessage(
            role: dto.role,
            content: dto.text ?? "",
            imageData: dto.attachments.first?.data.base64EncodedString()
        )
        message.id = dto.id
        message.timestamp = dto.createdAt ?? Date()
        return message
    }
}
