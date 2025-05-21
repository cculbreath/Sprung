//
//  AIModels.swift
//  PhysCloudResume
//
//  Created by Claude on 5/13/25.
//

import Foundation
import PDFKit
import AppKit
import SwiftUI

/// Constants for AI model identifiers
struct AIModels {
    // OpenAI models (only keeping the ones that are used)
    static let gpt4o = "gpt-4o"
    static let o4_mini = "o4-mini"
    static let gpt4o_mini = "gpt-4o-mini"
    static let gpt4_5 = "gpt-4.5-turbo"
    static let gpt4o_latest = "gpt-4o-2024-05-13"  // Latest version
    static let gpt_4o_mini_tts = "gpt-4o-mini-tts" // TTS model
    static let gpt4o_2024_08_06 = "gpt-4o-2024-08-06" // August 2024 update
    
    // Anthropic Claude models
    static let claude_3_opus = "claude-3-opus-20240229"
    static let claude_3_sonnet = "claude-3-sonnet-20240229"
    static let claude_3_haiku = "claude-3-haiku-20240307"
    static let claude_3_5_sonnet = "claude-3-5-sonnet-20240620"
    
    // xAI Grok models
    static let grok_1 = "grok-1"
    static let grok_1_5_mini = "grok-1.5-mini"
    static let grok_1_5 = "grok-1.5"
    
    // Google Gemini models
    static let gemini_pro = "gemini-pro"
    static let gemini_1_5_pro = "gemini-1.5-pro"
    static let gemini_1_5_flash = "gemini-1.5-flash"
    
    // Model provider prefixes for displaying and identifying models
    struct Provider {
        static let openai = "OpenAI"
        static let claude = "Claude"
        static let grok = "Grok"
        static let gemini = "Gemini"
    }
    
    // Check which provider a model belongs to
    static func providerForModel(_ model: String) -> String {
        let modelLower = model.lowercased()
        if modelLower.contains("gpt") || modelLower.contains("dalle") {
            return Provider.openai
        } else if modelLower.contains("claude") {
            return Provider.claude
        } else if modelLower.contains("grok") {
            return Provider.grok
        } else if modelLower.contains("gemini") {
            return Provider.gemini
        }
        return Provider.openai // Default to OpenAI for unknown models
    }
    
    /// Returns a friendly, human-readable name for a model
    /// - Parameter modelName: The raw model name
    /// - Returns: A simplified, user-friendly model name
    static func friendlyModelName(for modelName: String) -> String? {
        let components = modelName.split(separator: "-")
        
        // Handle different model naming patterns
        if modelName.lowercased().contains("gpt") {
            if components.count >= 2 {
                // Extract main version (e.g., "GPT-4" from "gpt-4-1106-preview")
                if components[1].allSatisfy({ $0.isNumber || $0 == "." }) { // Check if it's a version number like 4 or 3.5
                    return "GPT-\(components[1])"
                }
                
                // Handle mini variants
                if components.contains("mini") {
                    return "GPT-\(components[1]) Mini"
                }
                
                // Handle o4 models
                if components[0] == "o4" || components.contains("o") {
                    return "GPT-4o"
                }
            }
            
            // Special case for GPT-4o models
            if modelName.lowercased().contains("gpt-4o") {
                return "GPT-4o"
            }
        } 
        else if modelName.lowercased().contains("claude") {
            // Handle Claude models
            if components.count >= 2 {
                if components[1] == "3" && components.count >= 3 {
                    // Handle "claude-3-opus-20240229" -> "Claude 3 Opus"
                    return "Claude 3 \(components[2].capitalized)"
                } 
                else if components[1] == "3.5" && components.count >= 3 {
                    // Handle "claude-3.5-sonnet-20240620" -> "Claude 3.5 Sonnet"
                    return "Claude 3.5 \(components[2].capitalized)"
                }
                else {
                    // Handle other Claude versions
                    return "Claude \(components[1])"
                }
            }
        }
        else if modelName.lowercased().contains("grok") {
            // Handle Grok models
            if components.count >= 2 {
                return "Grok \(components[1])"
            }
            return "Grok"
        }
        else if modelName.lowercased().contains("gemini") {
            // Handle Gemini models
            if components.count >= 2 {
                if components.contains("pro") {
                    return "Gemini Pro"
                }
                if components.contains("flash") {
                    return "Gemini Flash"
                }
                return "Gemini \(components[1].capitalized)"
            }
            return "Gemini"
        }
        
        // Default fallback: Use the first part of the model name, capitalized
        return modelName.split(separator: "-").first?.capitalized
    }
}
