//
//  LLMVendorMapper.swift
//  PhysCloudResume
//
//  Centralized helpers for translating between vendor SDK types and
//  domain DTOs.
//

import Foundation
import SwiftOpenAI

enum LLMVendorMapper {
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

    static func dtoMessages(from vendorMessages: [LLMMessage]) -> [LLMMessageDTO] {
        vendorMessages.map { dtoMessage(from: $0) }
    }

    static func dtoMessage(from message: LLMMessage) -> LLMMessageDTO {
        let role = LLMRole(rawValue: message.role) ?? .assistant
        var textSegments: [String] = []
        var attachments: [LLMAttachment] = []

        switch message.content {
        case .text(let text):
            textSegments.append(text)
        case .contentArray(let contents):
            for item in contents {
                switch item {
                case .text(let text):
                    textSegments.append(text)
                case .imageUrl(let detail):
                    if let decoded = decodeDataURL(detail.url) {
                        attachments.append(LLMAttachment(data: decoded.data, mimeType: decoded.mimeType))
                    }
                default:
                    break
                }
            }
        @unknown default:
            break
        }

        let text = textSegments.isEmpty ? nil : textSegments.joined(separator: "\n")
        return LLMMessageDTO(
            role: role,
            text: text,
            attachments: attachments
        )
    }

    // MARK: - Response Conversion

    static func responseDTO(from response: LLMResponse) -> LLMResponseDTO {
        let createdDate = response.created.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let choices = (response.choices ?? []).enumerated().map { index, choice in
            LLMResponseChoiceDTO(
                index: choice.index ?? index,
                message: choice.message.map { dtoMessage(from: $0) },
                finishReason: finishReasonString(from: choice.finishReason)
            )
        }

        let usage = response.usage.map { usage -> LLMUsageDTO in
            LLMUsageDTO(
                promptTokens: usage.promptTokens ?? 0,
                completionTokens: usage.completionTokens ?? 0,
                totalTokens: usage.totalTokens ?? 0
            )
        }

        return LLMResponseDTO(
            id: response.id,
            model: response.model,
            created: createdDate,
            choices: choices,
            usage: usage
        )
    }

    static func streamChunkDTO(from chunk: ChatCompletionChunkObject) -> LLMStreamChunkDTO {
        guard let firstChoice = chunk.choices?.first else {
            return LLMStreamChunkDTO(content: nil, reasoning: nil, isFinished: false, finishReason: nil)
        }

        return LLMStreamChunkDTO(
            content: firstChoice.delta?.content,
            reasoning: firstChoice.delta?.reasoningContent,
            isFinished: firstChoice.finishReason != nil,
            finishReason: finishReasonString(from: firstChoice.finishReason)
        )
    }

    // MARK: - Helpers

    private static func finishReasonString(from value: IntOrStringValue?) -> String? {
        guard let value else { return nil }
        switch value {
        case .string(let stringValue):
            return stringValue
        case .int(let intValue):
            return String(intValue)
        }
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

    private static func decodeDataURL(_ url: URL) -> (data: Data, mimeType: String)? {
        guard url.scheme == "data" else { return nil }

        let absolute = url.absoluteString
        guard let commaIndex = absolute.firstIndex(of: ",") else { return nil }

        let metadata = String(absolute[..<commaIndex])
        let base64Part = String(absolute[absolute.index(after: commaIndex)...])

        let mimeType: String
        if let colonIndex = metadata.firstIndex(of: ":") {
            let typeSection = metadata[metadata.index(after: colonIndex)...]
            let components = typeSection.split(separator: ";", omittingEmptySubsequences: true)
            mimeType = components.first.map(String.init) ?? "application/octet-stream"
        } else {
            mimeType = "application/octet-stream"
        }

        guard let data = Data(base64Encoded: base64Part) else { return nil }
        return (data, mimeType)
    }

    private static func dtoMessage(from message: ChatCompletionObject.ChatChoice.ChatMessage) -> LLMMessageDTO {
        let role = LLMRole(rawValue: message.role ?? "") ?? .assistant
        var textSegments: [String] = []
        if let content = message.content, !content.isEmpty {
            textSegments.append(content)
        }
        if let reasoning = message.reasoningContent, !reasoning.isEmpty {
            textSegments.append(reasoning)
        }

        return LLMMessageDTO(
            role: role,
            text: textSegments.isEmpty ? nil : textSegments.joined(separator: "\n\n"),
            attachments: []
        )
    }
}
