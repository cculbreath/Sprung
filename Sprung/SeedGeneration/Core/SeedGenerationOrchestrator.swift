//
//  SeedGenerationOrchestrator.swift
//  Sprung
//
//  Main coordinator for the Seed Generation Module.
//  Manages the workflow from OI completion to ExperienceDefaults population.
//

import Foundation
import SwiftUI

/// Main coordinator for seed generation workflow
@Observable
@MainActor
final class SeedGenerationOrchestrator {
    // MARK: - State

    private(set) var context: SeedGenerationContext?
    private(set) var tasks: [GenerationTask] = []
    private(set) var reviewQueue: ReviewQueue = ReviewQueue()
    private(set) var activityTracker: SeedGenerationActivityTracker = SeedGenerationActivityTracker()

    private(set) var sectionProgress: [SectionProgress] = []

    /// User-selected generation constraints; adjustable mid-session
    /// (e.g. from the rejection-feedback form) so regenerations pick
    /// up the latest caps.
    private(set) var options: GenerationOptions = .load()

    private var isRunning = false

    // MARK: - Dependencies

    private let llmFacade: LLMFacade
    private let modelId: String
    private let backend: LLMFacade.Backend
    private let promptCacheService: PromptCacheService
    private let experienceDefaultsStore: ExperienceDefaultsStore

    // MARK: - Generators

    private let generators: [any SectionGenerator] = [
        WorkHighlightsGenerator(),
        VolunteerGenerator(),
        ProjectsGenerator(),
        SkillsGroupingGenerator(),
        TitleOptionsGenerator(),
        ObjectiveGenerator()
    ]

    // MARK: - Initialization

    init(
        context: SeedGenerationContext,
        llmFacade: LLMFacade,
        modelId: String,
        backend: LLMFacade.Backend = .openRouter,
        experienceDefaultsStore: ExperienceDefaultsStore
    ) {
        self.context = context
        self.llmFacade = llmFacade
        self.modelId = modelId
        self.backend = backend
        self.promptCacheService = PromptCacheService(backend: backend)
        self.experienceDefaultsStore = experienceDefaultsStore

        initializeSectionProgress()
        setupRegenerationCallback()
    }

    private func setupRegenerationCallback() {
        reviewQueue.onRegenerationRequested = { [weak self] itemId, originalContent, feedback in
            guard let self else { throw RegenerationError.noContext }
            return try await self.regenerateItem(itemId: itemId, originalContent: originalContent, feedback: feedback)
        }
    }

    private func initializeSectionProgress() {
        guard let context else { return }

        var enabledSections = context.enabledSections

        // Always add .custom if we have generators that use it (TitleOptions, Objective)
        // These generators produce content regardless of the custom section enablement
        if generators.contains(where: { $0.sectionKey == .custom }) {
            enabledSections.append(.custom)
        }

        // De-duplicate in case .custom was already present
        let uniqueSections = Array(Set(enabledSections))

        sectionProgress = uniqueSections.compactMap { section in
            // Only track sections we have generators for
            guard generators.contains(where: { $0.sectionKey == section }) else {
                return nil
            }
            return SectionProgress(section: section, status: .pending, totalTasks: 0, completedTasks: 0)
        }
    }

    // MARK: - Regeneration Errors

    enum RegenerationError: LocalizedError {
        case noContext
        case itemNotFound
        case generatorNotFound(String)
        case generationFailed(Error)

        var errorDescription: String? {
            switch self {
            case .noContext:
                return "Couldn't regenerate — session context is no longer available. Try restarting seed generation."
            case .itemNotFound:
                return "Couldn't regenerate — the item was not found in the queue."
            case .generatorNotFound(let name):
                return "Couldn't regenerate — no generator found for \(name)."
            case .generationFailed(let error):
                return "Regeneration failed — \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Section Progress

    struct SectionProgress: Identifiable {
        let section: ExperienceSectionKey
        var status: Status
        var totalTasks: Int
        var completedTasks: Int
        var failedTasks: Int = 0

        var id: String { section.rawValue }

        /// Non-nil when the section finished with at least one failure; use in UI to show a per-section error label.
        var failureMessage: String? {
            guard failedTasks > 0 else { return nil }
            return failedTasks == 1
                ? "1 item failed to generate"
                : "\(failedTasks) items failed to generate"
        }

        enum Status {
            case pending
            case running
            case completed
            case failed
        }
    }

    // MARK: - Generation Workflow

    func startGeneration(options: GenerationOptions) async {
        guard !isRunning, let context else { return }
        isRunning = true

        self.options = options
        options.save()

        let preamble = promptCacheService.buildPreamble(context: context)

        createAllTasks(context: context)
        await executeAllTasks(context: context, preamble: preamble)

        isRunning = false
    }

    /// Update generation constraints mid-session (e.g. from the
    /// rejection-feedback form). Subsequent regenerations use the new caps.
    func updateOptions(_ newOptions: GenerationOptions) {
        options = newOptions
        newOptions.save()
    }

    // MARK: - Task Creation

    private func createAllTasks(context: SeedGenerationContext) {
        for generator in generators {
            let generatorTypeName = String(describing: type(of: generator))
            var sectionTasks = generator.createTasks(context: context)

            // Tag each task with the generator type that created it
            for i in sectionTasks.indices {
                sectionTasks[i] = GenerationTask(
                    id: sectionTasks[i].id,
                    section: sectionTasks[i].section,
                    targetId: sectionTasks[i].targetId,
                    displayName: sectionTasks[i].displayName,
                    generatorType: generatorTypeName,
                    status: sectionTasks[i].status
                )
            }

            tasks.append(contentsOf: sectionTasks)

            // Update progress tracking
            if let index = sectionProgress.firstIndex(where: { $0.section == generator.sectionKey }) {
                sectionProgress[index].totalTasks += sectionTasks.count
            }
        }
    }

    // MARK: - Task Execution

    private func executeAllTasks(context: SeedGenerationContext, preamble: String) async {
        // Create execution config for generators
        let config = GeneratorExecutionConfig(
            llmFacade: llmFacade,
            modelId: modelId,
            backend: backend,
            preamble: preamble,
            experienceDefaultsStore: experienceDefaultsStore,
            options: options
        )

        for generator in generators {
            let generatorTypeName = String(describing: type(of: generator))
            // Filter tasks by the generator that created them, not just by section
            let generatorTasks = tasks.filter { $0.generatorType == generatorTypeName }

            guard !generatorTasks.isEmpty else { continue }

            updateSectionStatus(generator.sectionKey, to: .running)

            var sectionHadFailure = false

            for task in generatorTasks {
                activityTracker.startTask(id: task.id, displayName: task.displayName)

                do {
                    let content = try await generator.execute(
                        task: task,
                        context: context,
                        config: config
                    )

                    // Add to review queue
                    reviewQueue.add(task: task, content: content)

                    activityTracker.completeTask(id: task.id)
                    incrementCompletedCount(for: generator.sectionKey)

                } catch {
                    Logger.error("Task failed: \(task.displayName) - \(error)", category: .ai)
                    activityTracker.failTask(id: task.id, error: error.localizedDescription)
                    sectionHadFailure = true
                    incrementFailedCount(for: generator.sectionKey)
                }
            }

            updateSectionStatus(generator.sectionKey, to: sectionHadFailure ? .failed : .completed)
        }
    }

    // MARK: - Apply Approved Content

    /// Apply approved items that have not already been applied. Returns the IDs
    /// applied in this call so the caller can accumulate them and keep Apply
    /// enabled only for items approved after the last Apply — applying is
    /// incremental, never re-applying an item already written to defaults.
    @discardableResult
    func applyApprovedContent(
        to defaults: inout ExperienceDefaults,
        skipping alreadyApplied: Set<UUID> = []
    ) -> Set<UUID> {
        let itemsToApply = reviewQueue.approvedItems(excluding: alreadyApplied)

        for item in itemsToApply {
            let generator = generators.first { $0.sectionKey == item.task.section }

            // Determine the content to apply based on edit type
            let contentToApply: GeneratedContent
            if let editedChildren = item.editedChildren {
                // User edited array content - use editedChildren directly
                contentToApply = applyEditedChildren(editedChildren, to: item.generatedContent)
            } else if let editedContent = item.editedContent {
                // User edited scalar content - parse from text
                contentToApply = parseEditedContent(editedContent, originalContent: item.generatedContent)
            } else {
                // No edits - use original generated content
                contentToApply = item.generatedContent
            }

            generator?.apply(content: contentToApply, to: &defaults)
        }

        Logger.info("Applied \(itemsToApply.count) items to defaults", category: .ai)
        return Set(itemsToApply.map(\.id))
    }

    /// Apply edited children array directly to the content (no parsing needed)
    private func applyEditedChildren(_ children: [String], to originalContent: GeneratedContent) -> GeneratedContent {
        switch originalContent.type {
        case .workHighlights(let targetId, _):
            return GeneratedContent(type: .workHighlights(targetId: targetId, highlights: children))

        case .volunteerDescription(let targetId, let summary, _):
            return GeneratedContent(type: .volunteerDescription(targetId: targetId, summary: summary, highlights: children))

        case .projectDescription(let targetId, let description, _, let keywords):
            return GeneratedContent(type: .projectDescription(targetId: targetId, description: description, highlights: children, keywords: keywords))

        default:
            Logger.warning("applyEditedChildren called on non-array content type", category: .ai)
            return originalContent
        }
    }

    /// Parse user-edited text back into GeneratedContent structure
    private func parseEditedContent(_ editedText: String, originalContent: GeneratedContent) -> GeneratedContent {
        switch originalContent.type {
        case .workHighlights(let targetId, _):
            let highlights = parseArrayFromText(editedText)
            return GeneratedContent(type: .workHighlights(targetId: targetId, highlights: highlights))

        case .volunteerDescription(let targetId, _, _):
            // Parse summary and highlights from edited text
            let (summary, highlights) = parseDescriptionAndHighlights(editedText)
            return GeneratedContent(type: .volunteerDescription(targetId: targetId, summary: summary, highlights: highlights))

        case .projectDescription(let targetId, _, _, let keywords):
            // Parse description and highlights, keep keywords
            let (description, highlights) = parseDescriptionAndHighlights(editedText)
            return GeneratedContent(type: .projectDescription(targetId: targetId, description: description, highlights: highlights, keywords: keywords))

        case .objective:
            return GeneratedContent(type: .objective(summary: editedText.trimmingCharacters(in: .whitespacesAndNewlines)))

        case .skillGroups:
            // Round-trips the review sheet's editable format
            // ("Category Name: skill1, skill2" per line) back into groups.
            return GeneratedContent(type: .skillGroups(SkillGroup.parse(editableText: editedText)))

        default:
            // Unreachable via UI: ReviewItemCard only offers Edit for types
            // handled above. Surface loudly if that invariant ever breaks,
            // because falling back to the original discards the user's edit.
            Logger.error("Unhandled content type for edited content — applying ORIGINAL, user edit discarded: \(originalContent.type)", category: .ai)
            return originalContent
        }
    }

    /// Parse bullet-point text into array of strings
    private func parseArrayFromText(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { line in
                line.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "^[•\\-\\*]+\\s*", with: "", options: .regularExpression)
            }
            .filter { !$0.isEmpty }
    }

    /// Parse text that may contain description followed by bullet points
    private func parseDescriptionAndHighlights(_ text: String) -> (description: String, highlights: [String]) {
        let lines = text.components(separatedBy: .newlines)
        var descriptionParts: [String] = []
        var highlights: [String] = []
        var inHighlights = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // Check if this line starts a bullet list
            if trimmed.hasPrefix("-") || trimmed.hasPrefix("•") || trimmed.hasPrefix("*") {
                inHighlights = true
                let bulletText = trimmed
                    .replacingOccurrences(of: "^[•\\-\\*]+\\s*", with: "", options: .regularExpression)
                if !bulletText.isEmpty {
                    highlights.append(bulletText)
                }
            } else if inHighlights {
                // Non-bullet line after bullets started - treat as continuation or new highlight
                highlights.append(trimmed)
            } else {
                // Before bullets - part of description
                descriptionParts.append(trimmed)
            }
        }

        let description = descriptionParts.joined(separator: " ")
        return (description, highlights)
    }

    // MARK: - Regeneration

    /// Regenerate a rejected item with user feedback. Throws `RegenerationError` on failure
    /// so the caller can surface the reason to the user via `.regenerationFailed`.
    private func regenerateItem(
        itemId: UUID,
        originalContent: GeneratedContent,
        feedback: String?
    ) async throws -> GeneratedContent {
        guard let context else {
            throw RegenerationError.noContext
        }

        guard let item = reviewQueue.item(for: itemId) else {
            throw RegenerationError.itemNotFound
        }

        let generatorTypeName = item.task.generatorType
        guard let generator = generators.first(where: { String(describing: type(of: $0)) == generatorTypeName }) else {
            throw RegenerationError.generatorNotFound(generatorTypeName)
        }

        let preamble = promptCacheService.buildPreamble(context: context)
        let config = GeneratorExecutionConfig(
            llmFacade: llmFacade,
            modelId: modelId,
            backend: backend,
            preamble: preamble,
            experienceDefaultsStore: experienceDefaultsStore,
            options: options
        )

        do {
            return try await generator.regenerate(
                task: item.task,
                originalContent: originalContent,
                feedback: feedback,
                context: context,
                config: config
            )
        } catch {
            throw RegenerationError.generationFailed(error)
        }
    }

    // MARK: - Helpers

    private func updateSectionStatus(_ section: ExperienceSectionKey, to status: SectionProgress.Status) {
        if let index = sectionProgress.firstIndex(where: { $0.section == section }) {
            sectionProgress[index].status = status
        }
    }

    private func incrementCompletedCount(for section: ExperienceSectionKey) {
        if let index = sectionProgress.firstIndex(where: { $0.section == section }) {
            sectionProgress[index].completedTasks += 1
        }
    }

    private func incrementFailedCount(for section: ExperienceSectionKey) {
        if let index = sectionProgress.firstIndex(where: { $0.section == section }) {
            sectionProgress[index].failedTasks += 1
        }
    }
}
