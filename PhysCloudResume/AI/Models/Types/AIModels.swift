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
}
