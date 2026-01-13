//
//  SectionGenerator.swift
//  Sprung
//
//  Protocol defining how individual resume sections are generated.
//  Each generator knows how to create tasks from context and execute them.
//

import Foundation
import SwiftyJSON

/// Protocol for section-specific content generation.
/// Each generator handles one `ExperienceSectionKey` and knows how to:
/// - Create tasks from the generation context
/// - Execute individual tasks via LLM
/// - Apply approved content to ExperienceDefaults
protocol SectionGenerator {
    /// The section this generator handles
    var sectionKey: ExperienceSectionKey { get }

    /// Human-readable name for this generator
    var displayName: String { get }

    /// Generate tasks for this section based on context.
    /// For enumerated sections (work, education), creates one task per item.
    /// For aggregate sections (skills, titles), may create a single task.
    /// - Parameter context: The seed generation context with all OI data
    /// - Returns: Array of tasks to be executed
    func createTasks(context: SeedGenerationContext) -> [GenerationTask]

    /// Execute a single task, returning generated content.
    /// - Parameters:
    ///   - task: The task to execute
    ///   - context: The full generation context
    ///   - preamble: Cached preamble for prompt efficiency
    ///   - llmService: The LLM service to use for generation
    /// - Returns: Generated content for this task
    func execute(
        task: GenerationTask,
        context: SeedGenerationContext,
        preamble: String,
        llmService: any LLMServiceProtocol
    ) async throws -> GeneratedContent

    /// Apply approved content to ExperienceDefaults.
    /// Called after user approves generated content.
    /// - Parameters:
    ///   - content: The approved content to apply
    ///   - defaults: The ExperienceDefaults to update (inout)
    func apply(content: GeneratedContent, to defaults: inout ExperienceDefaults)
}

// MARK: - Default Implementations

extension SectionGenerator {
    /// Default display name derived from section key
    var displayName: String {
        sectionKey.rawValue.capitalized
    }
}

// MARK: - LLM Service Protocol

/// Protocol for LLM services that generators can use.
/// Abstracts over Anthropic, Gemini, or OpenRouter providers.
protocol LLMServiceProtocol: Sendable {
    /// Send a message and get a response.
    /// - Parameters:
    ///   - systemPrompt: The system prompt to use
    ///   - userPrompt: The user message/request
    ///   - maxTokens: Maximum tokens for the response
    /// - Returns: The LLM's text response
    func generate(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int
    ) async throws -> String

    /// Send a message expecting JSON output.
    /// - Parameters:
    ///   - systemPrompt: The system prompt to use
    ///   - userPrompt: The user message/request
    ///   - schema: JSON schema description for the expected output
    ///   - maxTokens: Maximum tokens for the response
    /// - Returns: Parsed JSON response
    func generateJSON(
        systemPrompt: String,
        userPrompt: String,
        schema: String,
        maxTokens: Int
    ) async throws -> JSON
}

// MARK: - Generator Errors

/// Errors that can occur during generation
enum GeneratorError: LocalizedError {
    case missingContext(String)
    case invalidTaskType(expected: String, got: String)
    case llmResponseParsingFailed(String)
    case timelineEntryNotFound(id: String)
    case contentTypeMismatch
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingContext(let detail):
            return "Missing required context: \(detail)"
        case .invalidTaskType(let expected, let got):
            return "Invalid task type: expected \(expected), got \(got)"
        case .llmResponseParsingFailed(let detail):
            return "Failed to parse LLM response: \(detail)"
        case .timelineEntryNotFound(let id):
            return "Timeline entry not found: \(id)"
        case .contentTypeMismatch:
            return "Generated content type does not match expected type"
        case .generationFailed(let detail):
            return "Generation failed: \(detail)"
        }
    }
}

// MARK: - Base Generator

/// Base class providing common functionality for generators.
/// Subclass this for standard section generators.
@MainActor
class BaseSectionGenerator: SectionGenerator {
    let sectionKey: ExperienceSectionKey

    /// Override this in subclasses to provide a custom display name
    var displayName: String {
        sectionKey.rawValue.capitalized
    }

    init(sectionKey: ExperienceSectionKey) {
        self.sectionKey = sectionKey
    }

    func createTasks(context: SeedGenerationContext) -> [GenerationTask] {
        // Subclasses override this
        fatalError("Subclasses must implement createTasks")
    }

    func execute(
        task: GenerationTask,
        context: SeedGenerationContext,
        preamble: String,
        llmService: any LLMServiceProtocol
    ) async throws -> GeneratedContent {
        // Subclasses override this
        fatalError("Subclasses must implement execute")
    }

    func apply(content: GeneratedContent, to defaults: inout ExperienceDefaults) {
        // Subclasses override this
        fatalError("Subclasses must implement apply")
    }

    // MARK: - Helper Methods

    /// Build the section-specific part of the prompt
    func buildSectionPrompt() -> String {
        // Subclasses can override for custom prompts
        return ""
    }

    /// Find a timeline entry by ID from the context
    func findTimelineEntry(id: String, in context: SeedGenerationContext) throws -> JSON {
        guard let entry = context.getTimelineEntry(id: id) else {
            throw GeneratorError.timelineEntryNotFound(id: id)
        }
        return entry
    }
}
