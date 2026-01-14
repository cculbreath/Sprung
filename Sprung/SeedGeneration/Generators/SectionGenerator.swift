//
//  SectionGenerator.swift
//  Sprung
//
//  Protocol defining how individual resume sections are generated.
//  Each generator knows how to create tasks from context and execute them.
//

import Foundation
import SwiftOpenAI
import SwiftyJSON

/// Configuration for generator execution
struct GeneratorExecutionConfig {
    let llmFacade: LLMFacade
    let modelId: String
    let backend: LLMFacade.Backend
    let preamble: String
    let anthropicSystemContent: [AnthropicSystemBlock]?

    init(
        llmFacade: LLMFacade,
        modelId: String,
        backend: LLMFacade.Backend,
        preamble: String,
        anthropicSystemContent: [AnthropicSystemBlock]? = nil
    ) {
        self.llmFacade = llmFacade
        self.modelId = modelId
        self.backend = backend
        self.preamble = preamble
        self.anthropicSystemContent = anthropicSystemContent
    }

    var usesAnthropicCaching: Bool {
        backend == .anthropic && anthropicSystemContent != nil
    }
}

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
    ///   - config: Execution configuration (LLM, model, backend, preamble)
    /// - Returns: Generated content for this task
    func execute(
        task: GenerationTask,
        context: SeedGenerationContext,
        config: GeneratorExecutionConfig
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
        config: GeneratorExecutionConfig
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

    // MARK: - Backend-Aware Execution Helpers

    /// Execute a structured JSON request with backend-aware caching.
    /// For Anthropic: uses direct API with cached system content and schema-enforced structured output
    /// For OpenRouter: uses standard structured output
    func executeStructuredRequest<T: Codable>(
        taskPrompt: String,
        systemPrompt: String,
        config: GeneratorExecutionConfig,
        responseType: T.Type,
        schema: [String: Any],
        schemaName: String
    ) async throws -> T {
        if config.backend == .anthropic {
            // Anthropic path: use cached system content + schema-enforced structured output
            return try await executeWithAnthropicCaching(
                taskPrompt: taskPrompt,
                systemPrompt: systemPrompt,
                config: config,
                responseType: responseType,
                schema: schema
            )
        } else {
            // OpenRouter path: use standard structured output
            let fullPrompt = "\(config.preamble)\n\n---\n\n\(taskPrompt)"
            return try await config.llmFacade.executeStructuredWithDictionarySchema(
                prompt: "\(systemPrompt)\n\n\(fullPrompt)",
                modelId: config.modelId,
                as: responseType,
                schema: schema,
                schemaName: schemaName
            )
        }
    }

    /// Execute with Anthropic caching and structured outputs - system content is cached, schema enforces format
    private func executeWithAnthropicCaching<T: Codable>(
        taskPrompt: String,
        systemPrompt: String,
        config: GeneratorExecutionConfig,
        responseType: T.Type,
        schema: [String: Any]
    ) async throws -> T {
        // Build system content with cache control on the preamble
        let cachedPreambleBlock = AnthropicSystemBlock(
            text: config.preamble,
            cacheControl: AnthropicCacheControl()
        )
        let systemInstructionBlock = AnthropicSystemBlock(text: systemPrompt)
        let systemContent = [cachedPreambleBlock, systemInstructionBlock]

        // Use Anthropic's structured output feature for schema-enforced JSON
        return try await config.llmFacade.executeStructuredWithAnthropicCaching(
            systemContent: systemContent,
            userPrompt: taskPrompt,
            modelId: config.modelId,
            responseType: responseType,
            schema: schema
        )
    }
}
