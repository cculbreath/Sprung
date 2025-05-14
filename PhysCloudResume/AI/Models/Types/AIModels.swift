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
    // OpenAI models
    static let gpt3_5 = "gpt-3.5-turbo"
    static let gpt4 = "gpt-4"
    static let gpt4_turbo = "gpt-4-turbo"
    static let gpt4o = "gpt-4o"
    static let gpt4o_mini = "gpt-4o-mini"
    static let gpt4_5 = "gpt-4.5-turbo"
    static let gpt4_5_preview = "gpt-4.5-preview"
    static let gpt4o_latest = "gpt-4o-2024-05-13"  // Latest version
    static let gpt_4o_mini_tts = "gpt-4o-mini-tts" // TTS model
    static let gpt4o_2024_08_06 = "gpt-4o-2024-08-06" // August 2024 update
    
    // Gemini models
    static let gemini_1_0_pro = "gemini-1.0-pro"
    static let gemini_1_0_pro_vision = "gemini-1.0-pro-vision"
    static let gemini_1_5_pro = "gemini-1.5-pro"
    static let gemini_1_5_pro_vision = "gemini-1.5-pro-vision"
    static let gemini_1_5_flash = "gemini-1.5-flash"
    static let gemini_2_0 = "gemini-2.0"
    static let gemini_2_5 = "gemini-2.5"
    static let gemini_2_0_flash = "gemini-2.0-flash"
    static let gemini_2_5_flash = "gemini-2.5-flash"
}
