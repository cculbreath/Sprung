//
//  LLMRequestBuilder.swift
//  Sprung
//
//  Created by Christopher Culbreath on 6/10/25.
//
import Foundation
import SwiftOpenAI
/// Reasoning configuration for OpenRouter (matches their API format exactly)
struct OpenRouterReasoning: Codable {
    /// Effort level: "high", "medium", or "low"
    let effort: String?
    /// Whether to exclude reasoning tokens from response (false = include, true = exclude)
    let exclude: Bool?
    /// Maximum tokens for reasoning
    let maxTokens: Int?
    enum CodingKeys: String, CodingKey {
        case effort
        case exclude
        case maxTokens = "max_tokens"
    }
    /// Convenience initializer with includeReasoning parameter
    init(effort: String? = nil, includeReasoning: Bool = true, maxTokens: Int? = nil) {
        self.effort = effort
        self.exclude = includeReasoning ? false : true  // false = include (don't exclude), true = exclude
        self.maxTokens = maxTokens
    }
}
/// Factory for assembling ChatCompletionParameters objects.
///
/// - Important: This is an internal implementation type. Use `LLMFacade` as the
///   public entry point for LLM operations.
struct _LLMRequestBuilder {
    /// Build parameters for a simple text request
    static func buildTextRequest(
        prompt: String,
        modelId: String,
        temperature: Double
    ) -> ChatCompletionParameters {
        let message = LLMMessage.text(role: .user, content: prompt)
        return ChatCompletionParameters(
            messages: [message],
            model: .custom(modelId),
            temperature: temperature
        )
    }
    /// Build parameters for a request with image inputs
    static func buildVisionRequest(
        prompt: String,
        modelId: String,
        images: [Data],
        temperature: Double
    ) -> ChatCompletionParameters {
        // Build content parts
        var contentParts: [ChatCompletionParameters.Message.ContentType.MessageContent] = [
            .text(prompt)
        ]
        // Add images
        for imageData in images {
            guard let imageDetail = _LLMVendorMapper.makeImageDetail(from: imageData) else {
                Logger.warning("⚠️ Skipping image attachment: failed to create data URL", category: .networking)
                continue
            }
            contentParts.append(.imageUrl(imageDetail))
        }
        // Create message
        let message = ChatCompletionParameters.Message(
            role: .user,
            content: .contentArray(contentParts)
        )
        return ChatCompletionParameters(
            messages: [message],
            model: .custom(modelId),
            temperature: temperature
        )
    }
    /// Build parameters for a structured JSON request with optional schema
    static func buildStructuredRequest<T: Codable>(
        prompt: String,
        modelId: String,
        responseType: T.Type,
        temperature: Double,
        jsonSchema: JSONSchema? = nil
    ) -> ChatCompletionParameters {
        let message = LLMMessage.text(role: .user, content: prompt)
        if let schema = jsonSchema {
            let responseFormatSchema = JSONSchemaResponseFormat(
                name: String(describing: responseType).lowercased(),
                strict: true,
                schema: schema
            )
            Logger.debug("📝 Using structured output with JSON Schema enforcement")
            return ChatCompletionParameters(
                messages: [message],
                model: .custom(modelId),
                responseFormat: .jsonSchema(responseFormatSchema),
                temperature: temperature
            )
        } else {
            Logger.debug("📝 Using basic JSON object mode (no schema enforcement)")
            return ChatCompletionParameters(
                messages: [message],
                model: .custom(modelId),
                responseFormat: .jsonObject,
                temperature: temperature
            )
        }
    }
    /// Build parameters for a structured request with images
    static func buildStructuredVisionRequest<T: Codable>(
        prompt: String,
        modelId: String,
        images: [Data],
        responseType: T.Type,
        temperature: Double
    ) -> ChatCompletionParameters {
        // Build content parts
        var contentParts: [ChatCompletionParameters.Message.ContentType.MessageContent] = [
            .text(prompt)
        ]
        // Add images
        for imageData in images {
            guard let imageDetail = _LLMVendorMapper.makeImageDetail(from: imageData) else {
                Logger.warning("⚠️ Skipping image attachment: failed to create data URL", category: .networking)
                continue
            }
            contentParts.append(.imageUrl(imageDetail))
        }
        // Create message
        let message = ChatCompletionParameters.Message(
            role: .user,
            content: .contentArray(contentParts)
        )
        return ChatCompletionParameters(
            messages: [message],
            model: .custom(modelId),
            responseFormat: .jsonObject,
            temperature: temperature
        )
    }
    /// Build parameters for a flexible JSON request (uses structured output when available)
    static func buildFlexibleJSONRequest<T: Codable>(
        prompt: String,
        modelId: String,
        responseType: T.Type,
        temperature: Double,
        jsonSchema: JSONSchema? = nil,
        supportsStructuredOutput: Bool,
        shouldAvoidJSONSchema: Bool
    ) -> ChatCompletionParameters {
        let message = LLMMessage.text(role: .user, content: prompt)
        if supportsStructuredOutput && !shouldAvoidJSONSchema {
            if let schema = jsonSchema {
                // Use full structured output with JSON schema enforcement
                let responseFormatSchema = JSONSchemaResponseFormat(
                    name: String(describing: responseType).lowercased(),
                    strict: true,
                    schema: schema
                )
                Logger.debug("📝 Using structured output with JSON Schema enforcement for model: \(modelId)")
                return ChatCompletionParameters(
                    messages: [message],
                    model: .custom(modelId),
                    responseFormat: .jsonSchema(responseFormatSchema),
                    temperature: temperature
                )
            } else {
                // Use basic JSON object format (still structured but no schema)
                Logger.debug("📝 Using structured output with JSON object mode for model: \(modelId)")
                return ChatCompletionParameters(
                    messages: [message],
                    model: .custom(modelId),
                    responseFormat: .jsonObject,
                    temperature: temperature
                )
            }
        } else {
            // Use basic mode - rely on prompt instructions for JSON formatting
            let reason = shouldAvoidJSONSchema ? "avoiding due to previous failures" : "model doesn't support structured output"
            Logger.debug("📝 Using basic mode with prompt-based JSON for model: \(modelId) (\(reason))")
            return ChatCompletionParameters(
                messages: [message],
                model: .custom(modelId),
                temperature: temperature
            )
        }
    }
    /// Build parameters for conversation requests
    static func buildConversationRequest(
        messages: [LLMMessageDTO],
        modelId: String,
        temperature: Double
    ) -> ChatCompletionParameters {
        let vendorMessages = _LLMVendorMapper.vendorMessages(from: messages)
        return ChatCompletionParameters(
            messages: vendorMessages,
            model: .custom(modelId),
            temperature: temperature
        )
    }
    /// Build parameters for structured conversation requests
    static func buildStructuredConversationRequest<T: Codable>(
        messages: [LLMMessageDTO],
        modelId: String,
        responseType: T.Type,
        temperature: Double,
        jsonSchema: JSONSchema? = nil
    ) -> ChatCompletionParameters {
        let vendorMessages = _LLMVendorMapper.vendorMessages(from: messages)
        if let schema = jsonSchema {
            let responseFormatSchema = JSONSchemaResponseFormat(
                name: String(describing: responseType).lowercased(),
                strict: true,
                schema: schema
            )
            Logger.debug("📝 Conversation using structured output with JSON Schema enforcement")
            return ChatCompletionParameters(
                messages: vendorMessages,
                model: .custom(modelId),
                responseFormat: .jsonSchema(responseFormatSchema),
                temperature: temperature
            )
        } else {
            Logger.debug("📝 Conversation using basic JSON object mode (no schema enforcement)")
            return ChatCompletionParameters(
                messages: vendorMessages,
                model: .custom(modelId),
                responseFormat: .jsonObject,
                temperature: temperature
            )
        }
    }

    /// Build parameters for a request with tool/function calling support
    static func buildToolRequest(
        messages: [ChatCompletionParameters.Message],
        modelId: String,
        tools: [ChatCompletionParameters.Tool],
        toolChoice: ToolChoice?,
        temperature: Double
    ) -> ChatCompletionParameters {
        Logger.debug("🔧 Building tool request with \(tools.count) tools for model: \(modelId)")
        return ChatCompletionParameters(
            messages: messages,
            model: .custom(modelId),
            toolChoice: toolChoice,
            tools: tools,
            parallelToolCalls: true,
            temperature: temperature
        )
    }
}
