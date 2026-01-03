//
//  DefaultModels.swift
//  Sprung
//
//  Centralized default model IDs by backend.
//  Update these when upgrading to newer model versions.
//

import Foundation

/// Centralized default model IDs by backend
enum DefaultModels {
    // MARK: - OpenRouter (provider/model format)

    /// Default OpenRouter model for general tasks
    static let openRouter = "openai/gpt-5-mini"

    /// Fast/cheap OpenRouter model for background processing
    static let openRouterFast = "google/gemini-2.5-flash"

    // MARK: - Gemini (Google AI direct)

    /// Default Gemini model for structured extraction
    static let gemini = "gemini-2.5-flash"

    /// High-quality Gemini model for complex tasks
    static let geminiPro = "gemini-2.5-pro"

    /// Lite Gemini model for simple/fast tasks
    static let geminiLite = "gemini-2.5-flash-lite"

    // MARK: - OpenAI Responses API (no prefix)

    /// Default OpenAI model for conversations
    static let openAI = "gpt-5-mini"

    /// Full OpenAI model for complex reasoning
    static let openAIFull = "gpt-5"

    // MARK: - Anthropic Direct API

    /// Default Anthropic model
    static let anthropic = "claude-sonnet-4-20250514"

    /// Fast Anthropic model
    static let anthropicFast = "claude-haiku-4-20250414"
}
