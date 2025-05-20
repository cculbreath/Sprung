//
//  ModelMappingExtension.swift
//  PhysCloudResume
//
//  Created by Claude on 5/18/25.
//

import Foundation
import SwiftOpenAI

/// Extension to map AI model strings to SwiftOpenAI Model enum
extension SwiftOpenAI.Model {
    /// Creates a Model from an AI model string
    /// - Parameter modelString: The model identifier string
    /// - Returns: The corresponding SwiftOpenAI Model
    static func from(_ modelString: String) -> SwiftOpenAI.Model {
        // Determine provider to apply appropriate mapping rules
        let provider = AIModels.providerForModel(modelString)
        
        // For non-OpenAI models, always use custom model directly to avoid compatibility issues
        if provider != AIModels.Provider.openai {
            Logger.debug("🔄 Using direct custom model mapping for \(provider) model: \(modelString)")
            
            // For Gemini models, ensure the modelString is passed directly without modification
            // This is critical as Google's OpenAI-compatible endpoint expects exact model names
            if provider == AIModels.Provider.gemini {
                Logger.debug("📝 Using exact model name for Gemini OpenAI compatibility: \(modelString)")
            }
            
            return .custom(modelString)
        }
        
        // OpenAI-specific mappings
        switch modelString {
        // GPT-4o variants
        case AIModels.gpt4o, "gpt-4o":
            return .gpt4o
        case AIModels.gpt4o_mini, "gpt-4o-mini":
            return .gpt4omini
        case AIModels.gpt4o_latest, "gpt-4o-2024-05-13":
            return .gpt4o20240513
        case AIModels.gpt4o_2024_08_06, "gpt-4o-2024-08-06":
            return .gpt4o20240806
            
        // GPT-4 variants
        case "gpt-4-turbo", "gpt-4-turbo-preview":
            return .gpt4TurboPreview
        case "gpt-4", "gpt-4-0613":
            return .gpt4
        case "gpt-4-32k", "gpt-4-32k-0613":
            return .custom("gpt-4-32k") // Not available in SwiftOpenAI enum
            
        // GPT-3.5 variants
        case "gpt-3.5-turbo", "gpt-3.5-turbo-0125":
            return .gpt35Turbo0125
        case "gpt-3.5-turbo-16k", "gpt-3.5-turbo-16k-0613":
            return .gpt35Turbo16k0613
            
        // Reasoning models
        case "o1-preview", "o1":
            return .o1Preview
        case "o1-mini":
            return .o1Mini
            
        // TTS models
        case AIModels.gpt_4o_mini_tts, "gpt-4o-mini-tts":
            return .custom("gpt-4o-mini-tts")
            
        // Additional models
        case "gpt-4-turbo-2024-04-09":
            return .gpt4Turbo20240409
        case "gpt-4-vision-preview":
            return .gpt4VisionPreview
        case "gpt-3.5-turbo-1106":
            return .gpt35Turbo1106
            
        // Default OpenAI models: treat as custom model
        default:
            Logger.debug("⚠️ Using custom model mapping for OpenAI model: \(modelString)")
            return .custom(modelString)
        }
    }
}


