//
//  LLMVendorMapper.swift
//  Sprung
//
//  Centralized helpers for translating between vendor SDK types and
//  domain DTOs.
//
import Foundation
import SwiftOpenAI
/// Centralized helpers for translating between vendor SDK types and domain DTOs.
///
/// - Important: This is an internal implementation type. Use `LLMFacade` as the
///   public entry point for LLM operations.
enum _LLMVendorMapper {
    // MARK: - Message Conversion
    static func vendorMessages(from dtoMessages: [LLMMessageDTO]) -> [LLMMessage] {
        dtoMessages.map { vendorMessage(from: $0) }
    }
    static func vendorMessage(from dto: LLMMessageDTO) -> LLMMessage {
        let role = ChatCompletionParameters.Message.Role(rawValue: dto.role.rawValue) ?? .assistant
        var contentParts: [ChatCompletionParameters.Message.ContentType.MessageContent] = []
        if let text = dto.text, !text.isEmpty {
            contentParts.append(.text(text))
        }
        if !dto.attachments.isEmpty {
            for attachment in dto.attachments {
                guard let detail = makeImageDetail(from: attachment.data, mimeType: attachment.mimeType) else {
                    Logger.warning("⚠️ Skipping attachment due to invalid data URL", category: .networking)
                    continue
                }
                contentParts.append(.imageUrl(detail))
            }
        }
        if contentParts.isEmpty {
            return LLMMessage.text(role: role, content: dto.text ?? "")
        }
        if contentParts.count == 1, case let .text(text) = contentParts[0], dto.attachments.isEmpty {
            return LLMMessage.text(role: role, content: text)
        }
        return ChatCompletionParameters.Message(
            role: role,
            content: .contentArray(contentParts)
        )
    }
    // MARK: - Response Conversion
    static func responseDTO(from response: LLMResponse) -> LLMResponseDTO {
        let choices = (response.choices ?? []).map { choice in
            let messageDTO: LLMMessageDTO? = choice.message.flatMap { message in
                let role = LLMRole(rawValue: message.role ?? "") ?? .assistant
                let segments = [message.content, message.reasoningContent]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                let text = segments.isEmpty ? nil : segments.joined(separator: "\n\n")
                return LLMMessageDTO(role: role, text: text, attachments: [])
            }
            return LLMResponseChoiceDTO(message: messageDTO)
        }
        return LLMResponseDTO(choices: choices)
    }
    static func streamChunkDTO(from chunk: ChatCompletionChunkObject) -> LLMStreamChunkDTO {
        guard let firstChoice = chunk.choices?.first else {
            return LLMStreamChunkDTO(content: nil, reasoning: nil, isFinished: false)
        }
        return LLMStreamChunkDTO(
            content: firstChoice.delta?.content,
            reasoning: firstChoice.delta?.reasoningContent,
            isFinished: firstChoice.finishReason != nil
        )
    }
    static func makeImageDetail(
        from data: Data,
        mimeType: String = "image/png"
    ) -> ChatCompletionParameters.Message.ContentType.MessageContent.ImageDetail? {
        let base64Image = data.base64EncodedString()
        let urlString = "data:\(mimeType);base64,\(base64Image)"
        guard let imageURL = URL(string: urlString) else {
            Logger.error("❌ Failed to build data URL for image attachment", category: .networking)
            return nil
        }
        return ChatCompletionParameters.Message.ContentType.MessageContent.ImageDetail(url: imageURL)
    }
}
