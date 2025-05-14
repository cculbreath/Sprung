//
//  OpenAIModelExtension.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/25/25.
//

import Foundation
import PDFKit
import AppKit
import SwiftUI
import OpenAI

// Import AIModels for use in this file
// The models are now defined in AIModels.swift

// Extension to AudioSpeechQuery for TTS models
extension AudioSpeechQuery {
    // Adding the GPT-4o mini TTS model to the available models
    enum CustomTTSModels {
        // You can use this directly in code as .gpt4o_mini_tts
        static let gpt4o_mini_tts = AIModels.gpt_4o_mini_tts
    }
}
