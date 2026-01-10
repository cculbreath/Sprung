//
//  OnboardingLLMConfig.swift
//  Sprung
//
//  Centralized LLM configuration constants for the Onboarding Interview.
//  Consolidates magic numbers and configuration values from LLMMessenger,
//  AnthropicRequestBuilder, and various agent files.
//

import Foundation

/// Centralized LLM configuration constants for the Onboarding Interview
enum OnboardingLLMConfig {
    // MARK: - Token Limits

    /// Maximum tokens for LLM response generation
    static let maxTokens = 4096

    /// Maximum context tokens for the model
    static let maxContextTokens = 100_000

    // MARK: - Generation Parameters

    /// Temperature for LLM generation (1.0 = default, creative)
    static let temperature: Double = 1.0

    /// Top-P for nucleus sampling (1.0 = consider all tokens)
    static let topP: Double = 1.0

    // MARK: - Retry Configuration

    /// Maximum number of retry attempts for transient errors
    static let maxRetries = 3

    /// Initial delay before first retry (seconds)
    static let initialRetryDelay: TimeInterval = 2.0

    /// Maximum delay between retries (seconds)
    static let maxRetryDelay: TimeInterval = 30.0

    // MARK: - Timeouts

    /// Timeout for LLM stream operations (seconds)
    static let streamTimeout: TimeInterval = 120.0

    /// Timeout for tool execution (seconds)
    static let toolExecutionTimeout: TimeInterval = 60.0

    // MARK: - Agent Limits

    /// Maximum turns for multi-turn agent loops
    static let maxAgentTurns = 50

    // MARK: - Concurrency

    /// Default maximum concurrent extractions
    static let defaultMaxConcurrentExtractions = 5

    // MARK: - Model Defaults (see DefaultModels.swift for model IDs)

    // Model IDs are centralized in DefaultModels.swift to avoid duplication
    // Use DefaultModels.anthropic, DefaultModels.anthropicFast, etc.
}
