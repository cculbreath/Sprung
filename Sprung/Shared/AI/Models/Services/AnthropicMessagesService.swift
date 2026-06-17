//
//  AnthropicMessagesService.swift
//  Sprung
//
//  Interface-segregation seam for the Anthropic Messages API surface that
//  `LLMFacade` exposes. The facade itself remains the concrete entry point and
//  forwards each method to `LLMFacadeSpecializedAPIs` (which owns the real
//  logic); this protocol simply names the narrow Anthropic-only slice of that
//  surface so consumers can eventually depend on the segregated interface
//  instead of the whole facade.
//
//  NOTE: Consumers are intentionally NOT repointed in this slice — they still
//  hold `LLMFacade`. Adding the conformance is byte- and behavior-neutral.
//

import Foundation
import SwiftOpenAI

/// The Anthropic Messages API surface exposed by `LLMFacade`.
///
/// Every method here mirrors a one-line delegation on `LLMFacade` that forwards
/// to `LLMFacadeSpecializedAPIs`. Conformance is declared via an empty extension
/// on `LLMFacade` — no method bodies move and no behavior changes.
@MainActor
protocol AnthropicMessagesService: AnyObject {

    // MARK: - Messages

    /// Streaming Anthropic Messages call.
    func anthropicMessagesStream(
        parameters: AnthropicMessageParameter
    ) async throws -> AsyncThrowingStream<AnthropicStreamEvent, Error>

    /// Non-streaming Anthropic Messages call — used by multi-turn agent loops
    /// (git analysis, card merge) where the full response is consumed at once.
    func anthropicMessages(
        parameters: AnthropicMessageParameter
    ) async throws -> AnthropicMessageResponse

    /// List the available Anthropic models.
    func anthropicListModels() async throws -> AnthropicModelsResponse

    // MARK: - Files API & Token Counting

    /// Upload a file to the Anthropic Files API for use in document blocks.
    func anthropicUploadFile(data: Data, filename: String, mimeType: String) async throws -> AnthropicFileMetadata

    /// Delete a file from the Anthropic Files API.
    func anthropicDeleteFile(id: String) async throws -> AnthropicFileDeletedResponse

    /// Count tokens for a prospective Anthropic Messages API request.
    func anthropicCountTokens(parameters: AnthropicTokenCountParameter) async throws -> AnthropicTokenCountResponse

    // MARK: - Caching Execution Helpers

    /// Execute a text prompt via direct Anthropic API with prompt caching.
    func executeTextWithAnthropicCaching(
        systemContent: [AnthropicSystemBlock],
        userPrompt: String,
        modelId: String
    ) async throws -> String

    /// Execute a structured JSON request via direct Anthropic API with prompt
    /// caching and schema enforcement.
    func executeStructuredWithAnthropicCaching<T: Codable>(
        systemContent: [AnthropicSystemBlock],
        userPrompt: String,
        modelId: String,
        responseType: T.Type,
        schema: [String: Any]
    ) async throws -> T

    /// Execute a structured JSON request whose user content is arbitrary
    /// Anthropic content blocks (document blocks with cache control, etc.).
    func executeStructuredWithAnthropicBlocks<T: Codable>(
        systemContent: [AnthropicSystemBlock],
        userBlocks: [AnthropicContentBlock],
        modelId: String,
        responseType: T.Type,
        schema: [String: Any],
        maxTokens: Int
    ) async throws -> T
}

// MARK: - LLMFacade Conformance

/// `LLMFacade` already implements every method above with matching signatures,
/// so conformance is purely declarative. The `executeStructuredWithAnthropicBlocks`
/// default argument (`maxTokens: Int = 8192`) on the facade satisfies the
/// protocol's non-defaulted requirement.
extension LLMFacade: AnthropicMessagesService {}
