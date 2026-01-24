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
    let experienceDefaultsStore: ExperienceDefaultsStore?

    init(
        llmFacade: LLMFacade,
        modelId: String,
        backend: LLMFacade.Backend,
        preamble: String,
        anthropicSystemContent: [AnthropicSystemBlock]? = nil,
        experienceDefaultsStore: ExperienceDefaultsStore? = nil
    ) {
        self.llmFacade = llmFacade
        self.modelId = modelId
        self.backend = backend
        self.preamble = preamble
        self.anthropicSystemContent = anthropicSystemContent
        self.experienceDefaultsStore = experienceDefaultsStore
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
@MainActor
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

    /// Regenerate content after rejection with user feedback.
    /// - Parameters:
    ///   - task: The original task
    ///   - originalContent: The content that was rejected
    ///   - feedback: User's feedback explaining why (nil if rejected without comment)
    ///   - context: The full generation context
    ///   - config: Execution configuration
    /// - Returns: New generated content incorporating the feedback
    func regenerate(
        task: GenerationTask,
        originalContent: GeneratedContent,
        feedback: String?,
        context: SeedGenerationContext,
        config: GeneratorExecutionConfig
    ) async throws -> GeneratedContent
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

    func regenerate(
        task: GenerationTask,
        originalContent: GeneratedContent,
        feedback: String?,
        context: SeedGenerationContext,
        config: GeneratorExecutionConfig
    ) async throws -> GeneratedContent {
        // Default implementation: subclasses should override for custom regeneration logic
        // This base implementation just re-executes with feedback in the prompt
        fatalError("Subclasses must implement regenerate")
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

    /// Build regeneration context from original content and feedback
    func buildRegenerationContext(originalContent: GeneratedContent, feedback: String?) -> String {
        var context = "## Previous Generation (REJECTED)\n\n"

        // Format the original content based on type
        switch originalContent.type {
        case .workHighlights(_, let highlights):
            context += "The following highlights were rejected:\n"
            for highlight in highlights {
                context += "- \(highlight)\n"
            }

        case .educationDescription(_, let description, let courses):
            context += "Description: \(description)\n"
            if !courses.isEmpty {
                context += "Courses: \(courses.joined(separator: ", "))\n"
            }

        case .volunteerDescription(_, let summary, let highlights):
            context += "Summary: \(summary)\n"
            for highlight in highlights {
                context += "- \(highlight)\n"
            }

        case .projectDescription(_, let description, let highlights, let keywords):
            context += "Description: \(description)\n"
            for highlight in highlights {
                context += "- \(highlight)\n"
            }
            if !keywords.isEmpty {
                context += "Keywords: \(keywords.joined(separator: ", "))\n"
            }

        case .objective(let summary):
            context += "Summary: \(summary)\n"

        case .skillGroups(let groups):
            for group in groups {
                context += "\(group.name): \(group.keywords.joined(separator: ", "))\n"
            }

        case .titleSets(let sets):
            for set in sets {
                context += "- \(set.titles.joined(separator: " | ")) (\(set.emphasis.rawValue))\n"
            }

        case .workSummary(_, let summary):
            context += "Summary: \(summary)\n"

        case .awardSummary(_, let summary):
            context += "Summary: \(summary)\n"

        case .publicationSummary(_, let summary):
            context += "Summary: \(summary)\n"

        case .languages(let entries):
            for entry in entries {
                context += "- \(entry.language): \(entry.fluency)\n"
            }

        case .interests(let entries):
            for entry in entries {
                context += "- \(entry.name): \(entry.keywords.joined(separator: ", "))\n"
            }

        case .customField(let key, let values):
            context += "\(key): \(values.joined(separator: ", "))\n"

        case .certificate, .reference, .rawJSON:
            context += "(Content details not available for display)\n"
        }

        context += "\n## User Feedback\n\n"
        if let feedback = feedback, !feedback.isEmpty {
            context += feedback
            context += "\n\n## Instructions\n\nRevise the content based on the user's feedback. You may keep parts that weren't criticized, but address the specific issues mentioned."
        } else {
            context += "The user rejected this content without providing specific feedback."
            context += "\n\n## Instructions\n\nGenerate a significantly different alternative. Since no specific feedback was provided, try a different approach or emphasis."
        }

        return context
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
