//
//  LLMRequestBuilder.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 6/10/25.
//

import Foundation
import SwiftOpenAI

/// Factory for assembling ChatCompletionParameters objects
struct LLMRequestBuilder {
    
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
            let base64Image = imageData.base64EncodedString()
            let imageURL = URL(string: "data:image/png;base64,\(base64Image)")!
            let imageDetail = ChatCompletionParameters.Message.ContentType.MessageContent.ImageDetail(url: imageURL)
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
            let base64Image = imageData.base64EncodedString()
            let imageURL = URL(string: "data:image/png;base64,\(base64Image)")!
            let imageDetail = ChatCompletionParameters.Message.ContentType.MessageContent.ImageDetail(url: imageURL)
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
        messages: [LLMMessage],
        modelId: String,
        temperature: Double
    ) -> ChatCompletionParameters {
        return ChatCompletionParameters(
            messages: messages,
            model: .custom(modelId),
            temperature: temperature
        )
    }
    
    /// Build parameters for structured conversation requests
    static func buildStructuredConversationRequest<T: Codable>(
        messages: [LLMMessage],
        modelId: String,
        responseType: T.Type,
        temperature: Double,
        jsonSchema: JSONSchema? = nil
    ) -> ChatCompletionParameters {
        if let schema = jsonSchema {
            let responseFormatSchema = JSONSchemaResponseFormat(
                name: String(describing: responseType).lowercased(),
                strict: true,
                schema: schema
            )
            Logger.debug("📝 Conversation using structured output with JSON Schema enforcement")
            return ChatCompletionParameters(
                messages: messages,
                model: .custom(modelId),
                responseFormat: .jsonSchema(responseFormatSchema),
                temperature: temperature
            )
        } else {
            Logger.debug("📝 Conversation using basic JSON object mode (no schema enforcement)")
            return ChatCompletionParameters(
                messages: messages,
                model: .custom(modelId),
                responseFormat: .jsonObject,
                temperature: temperature
            )
        }
    }
}