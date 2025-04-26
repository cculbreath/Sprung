//
//  OpenAIModelExtension.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/25/25.
//

import Foundation
import OpenAI

// Constants for OpenAI model names
// These are defined as String constants that can be used directly with the API
enum AIModels {
    // GPT-4.5 family of models
    static let gpt4_5 = "gpt-4.5"
    static let gpt4_5_preview = "gpt-4.5-preview"

    // GPT-4o family of models
    static let gpt4o_mini = "gpt-4o-mini"
    static let gpt4o = "gpt-4o"
    static let gpt4o_latest = "gpt-4o" // Map latest to the current model

    // GPT-4o TTS model
    static let gpt_4o_mini_tts = "gpt-4o-mini-tts"
}

// Extension to AudioSpeechQuery for TTS models
extension AudioSpeechQuery {
    // Adding the GPT-4o mini TTS model to the available models
    enum CustomTTSModels {
        // You can use this directly in code as .gpt4o_mini_tts
        static let gpt4o_mini_tts = AIModels.gpt_4o_mini_tts
    }
}
