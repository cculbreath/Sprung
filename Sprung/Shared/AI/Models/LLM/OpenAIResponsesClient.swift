//
//  OpenAIResponsesClient.swift
//  Sprung
//
//  LLMClient implementation backed by the OpenAI Responses API. This keeps
//  vendor SDK types localized and allows the facade to route requests to OpenAI
//  without exposing SwiftOpenAI primitives to the rest of the app.
//
import Foundation
import SwiftOpenAI
/// LLMClient implementation backed by the OpenAI Responses API.
///
/// - Important: This is an internal implementation type. Use `LLMFacade` as the
///   public entry point for LLM operations. Do not instantiate directly outside
///   of `LLMFacadeFactory`.
final class OpenAIResponsesClient: LLMClient {
    private let service: OpenAIService
    private let decoder = JSONDecoder()
    init(service: OpenAIService) {
        self.service = service
    }
    func executeText(
        prompt: String,
        modelId: String
    ) async throws -> String {
        try await requestText(
            prompt: prompt,
            modelId: modelId,
            images: []
        )
    }
    func executeTextWithImages(
        prompt: String,
        modelId: String,
        images: [Data]
    ) async throws -> String {
        try await requestText(
            prompt: prompt,
            modelId: modelId,
            images: images
        )
    }
    func executeStructured<T>(
        prompt: String,
        modelId: String,
        as type: T.Type
    ) async throws -> T where T: Codable & Sendable {
        let raw = try await requestText(
            prompt: prompt,
            modelId: modelId,
            images: []
        )
        return try decode(raw, as: type)
    }
    func executeStructuredWithImages<T>(
        prompt: String,
        modelId: String,
        images: [Data],
        as type: T.Type
    ) async throws -> T where T: Codable & Sendable {
        let raw = try await requestText(
            prompt: prompt,
            modelId: modelId,
            images: images
        )
        return try decode(raw, as: type)
    }

    func executeStructuredWithSchema<T>(
        prompt: String,
        modelId: String,
        as type: T.Type,
        schema: JSONSchema,
        schemaName: String
    ) async throws -> T where T: Codable & Sendable {
        let raw = try await requestStructured(
            prompt: prompt,
            modelId: modelId,
            schema: schema,
            schemaName: schemaName
        )
        return try decode(raw, as: type)
    }

    // MARK: - Private
    private func requestText(
        prompt: String,
        modelId: String,
        images: [Data]
    ) async throws -> String {
        let response = try await performRequest(
            prompt: prompt,
            modelId: modelId,
            images: images,
            textConfig: TextConfiguration(format: .text)
        )
        guard let text = extractText(from: response), !text.isEmpty else {
            throw LLMError.unexpectedResponseFormat
        }
        return text
    }

    private func requestStructured(
        prompt: String,
        modelId: String,
        schema: JSONSchema,
        schemaName: String
    ) async throws -> String {
        let textConfig = TextConfiguration(format: .jsonSchema(schema, name: schemaName))
        let response = try await performRequest(
            prompt: prompt,
            modelId: modelId,
            images: [],
            textConfig: textConfig
        )
        guard let text = extractText(from: response), !text.isEmpty else {
            throw LLMError.unexpectedResponseFormat
        }
        return text
    }
    private func performRequest(
        prompt: String,
        modelId: String,
        images: [Data],
        textConfig: TextConfiguration
    ) async throws -> ResponseModel {
        var content: [ContentItem] = [
            .text(TextContent(text: prompt))
        ]
        for imageData in images {
            let imageContent = ImageContent(
                detail: "auto",
                fileId: nil,
                imageUrl: dataURL(for: imageData)
            )
            content.append(.image(imageContent))
        }
        let message = InputMessage(role: "user", content: .array(content))
        let inputItems: [InputItem] = [.message(message)]
        let parameters = ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(modelId),
            store: true,
            text: textConfig
        )
        return try await service.responseCreate(parameters)
    }
    private func dataURL(for data: Data, mimeType: String = "image/png") -> String {
        let base64 = data.base64EncodedString()
        return "data:\(mimeType);base64,\(base64)"
    }
    private func decode<T>(_ raw: String, as type: T.Type) throws -> T where T: Codable {
        guard let data = raw.data(using: .utf8) else {
            throw LLMError.unexpectedResponseFormat
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw LLMError.decodingFailed(error)
        }
    }
    private func extractText(from response: ResponseModel) -> String? {
        if let output = response.outputText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !output.isEmpty {
            return output
        }
        for item in response.output {
            if case let .message(message) = item {
                for content in message.content {
                    if case let .outputText(output) = content,
                       !output.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return output.text
                    }
                }
            }
        }
        return nil
    }
}
