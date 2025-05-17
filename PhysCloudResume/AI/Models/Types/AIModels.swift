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
    static let gpt4o_mini = "gpt-4o-mini"
    static let gpt4_5 = "gpt-4.5-turbo"
    static let gpt4o_latest = "gpt-4o-2024-05-13"  // Latest version
    static let gpt_4o_mini_tts = "gpt-4o-mini-tts" // TTS model
    static let gpt4o_2024_08_06 = "gpt-4o-2024-08-06" // August 2024 update
    
    // Gemini models (only keeping the ones that are used)
    static let gemini_1_0_pro = "gemini-1.0-pro"
    static let gemini_1_5_pro = "gemini-1.5-pro"
    static let gemini_1_5_flash = "gemini-1.5-flash"
}
