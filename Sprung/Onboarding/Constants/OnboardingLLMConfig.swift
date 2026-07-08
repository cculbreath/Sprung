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
    /// (8K headroom for synthesis-heavy interview turns; streaming is always on)
    static let maxTokens = 8192

}
