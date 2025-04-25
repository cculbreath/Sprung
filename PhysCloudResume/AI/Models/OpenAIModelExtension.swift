//
//  OpenAIModelExtension.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/25/25.
//

import Foundation
import OpenAI

// Extension for OpenAI models to include newer model variations
public extension ChatQuery.Model {
    /// GPT-4.5 family of models
    static let gpt4_5 = "gpt-4.5"
    static let gpt4_5_preview = "gpt-4.5-preview"
    
    /// GPT-4o family of models
    static let gpt4o_mini = "gpt-4o-mini"
}

// Extension for audio speech models
public extension AudioSpeechQuery.AudioSpeechModel {
    /// GPT-4o mini TTS model
    static let gpt_4o_mini_tts = "gpt-4o-mini-tts"
}