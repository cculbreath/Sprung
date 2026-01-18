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

    private(set) var projectProposals: [ProjectProposal]?
    private(set) var generatedSkillGroups: [SkillGroup]?
    private(set) var generatedTitleSets: [TitleSet]?
    private(set) var generatedObjective: String?
    private(set) var sectionProgress: [SectionProgress] = []

    private var isRunning = false

    // MARK: - Dependencies

    private let llmFacade: LLMFacade
    private let modelId: String
    private let backend: LLMFacade.Backend
    private let promptCacheService: PromptCacheService
    private let parallelExecutor: ParallelLLMExecutor
    private let experienceDefaultsStore: ExperienceDefaultsStore

    // MARK: - Generators

    private let generators: [any SectionGenerator] = [
        WorkHighlightsGenerator(),
        EducationGenerator(),
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
        self.parallelExecutor = ParallelLLMExecutor()
        self.experienceDefaultsStore = experienceDefaultsStore

        initializeSectionProgress()
        setupRegenerationCallback()
    }

    private func setupRegenerationCallback() {
        reviewQueue.onRegenerationRequested = { [weak self] itemId, originalContent, feedback in
            guard let self else { return nil }
            return await self.regenerateItem(itemId: itemId, originalContent: originalContent, feedback: feedback)
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

    // MARK: - Section Progress

    struct SectionProgress: Identifiable {
        let section: ExperienceSectionKey
        var status: Status
        var totalTasks: Int
        var completedTasks: Int

        var id: String { section.rawValue }

        enum Status {
            case pending
            case running
            case completed
            case failed
        }
    }

    // MARK: - Generation Workflow

    func startGeneration() async {
        guard !isRunning, let context else { return }
        isRunning = true

        let preamble = promptCacheService.buildPreamble(context: context)

        // Phase 1: Discover projects (special workflow) - use preamble for full KC context
        await discoverProjects(context: context, preamble: preamble)

        // Phase 2: Create tasks for all sections
        createAllTasks(context: context)

        // Phase 3: Execute tasks in parallel
        await executeAllTasks(context: context, preamble: preamble)

        isRunning = false
    }

    // MARK: - Project Discovery

    private func discoverProjects(context: SeedGenerationContext, preamble: String) async {
        guard let projectsGenerator = generators.first(where: { $0 is ProjectsGenerator }) as? ProjectsGenerator else {
            return
        }

        updateSectionStatus(.projects, to: .running)

        do {
            let proposals = try await projectsGenerator.discoverProjects(
                context: context,
                llmFacade: llmFacade,
                modelId: modelId,
                backend: backend,
                preamble: preamble,
                experienceDefaultsStore: experienceDefaultsStore
            )
            projectProposals = proposals
            Logger.info("Discovered \(proposals.count) project proposals", category: .ai)
        } catch {
            Logger.error("Project discovery failed: \(error)", category: .ai)
            updateSectionStatus(.projects, to: .failed)
        }
    }

    // MARK: - Task Creation

    private func createAllTasks(context: SeedGenerationContext) {
        for generator in generators {
            // Skip projects if we have proposals (handled separately)
            if generator is ProjectsGenerator, projectProposals != nil {
                continue
            }

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
            experienceDefaultsStore: experienceDefaultsStore
        )

        for generator in generators {
            let generatorTypeName = String(describing: type(of: generator))
            // Filter tasks by the generator that created them, not just by section
            let generatorTasks = tasks.filter { $0.generatorType == generatorTypeName }

            guard !generatorTasks.isEmpty else { continue }

            updateSectionStatus(generator.sectionKey, to: .running)

            for task in generatorTasks {
                activityTracker.startTask(id: task.id, displayName: task.displayName)

                do {
                    let content = try await generator.execute(
                        task: task,
                        context: context,
                        config: config
                    )

                    // Handle special cases - capture for dedicated views
                    switch content.type {
                    case .skillGroups(let groups):
                        generatedSkillGroups = groups
                    case .titleSets(let sets):
                        generatedTitleSets = sets
                    case .objective(let summary):
                        generatedObjective = summary
                    default:
                        break
                    }

                    // Add to review queue
                    reviewQueue.add(task: task, content: content)

                    activityTracker.completeTask(id: task.id)
                    incrementCompletedCount(for: generator.sectionKey)

                } catch {
                    Logger.error("Task failed: \(task.displayName) - \(error)", category: .ai)
                    activityTracker.failTask(id: task.id, error: error.localizedDescription)
                }
            }

            updateSectionStatus(generator.sectionKey, to: .completed)
        }
    }

    // MARK: - Project Curation

    func approveProject(_ proposal: ProjectProposal) {
        guard var proposals = projectProposals,
              let index = proposals.firstIndex(where: { $0.id == proposal.id }) else {
            return
        }

        proposals[index].isApproved = true
        projectProposals = proposals

        // Save project shell to ExperienceDefaults immediately
        // The proposal's UUID becomes the project's ID for later lookup
        let projectEntry = ProjectExperienceDraft(
            id: proposal.id,
            name: proposal.name,
            description: proposal.description,
            startDate: "",
            endDate: "",
            url: "",
            organization: "",
            type: "",
            highlights: [],
            keywords: [],
            roles: []
        )

        let defaults = experienceDefaultsStore.currentDefaults()
        defaults.projects.append(projectEntry)
        experienceDefaultsStore.save(defaults)
        Logger.info("Saved approved project to ExperienceDefaults: \(proposal.name)", category: .ai)
    }

    func rejectProject(_ proposal: ProjectProposal) {
        guard var proposals = projectProposals else { return }
        proposals.removeAll { $0.id == proposal.id }
        projectProposals = proposals
    }

    func generateApprovedProjects() async {
        guard let context,
              let proposals = projectProposals,
              let projectsGenerator = generators.first(where: { $0 is ProjectsGenerator }) as? ProjectsGenerator else {
            return
        }

        let approvedProposals = proposals.filter { $0.isApproved }
        guard !approvedProposals.isEmpty else {
            // No approved projects - mark as completed with 0 tasks
            updateSectionStatus(.projects, to: .completed)
            return
        }

        let projectTasks = projectsGenerator.createTasks(for: approvedProposals, context: context)
        tasks.append(contentsOf: projectTasks)

        // Update progress tracking for projects section
        if let index = sectionProgress.firstIndex(where: { $0.section == .projects }) {
            sectionProgress[index].totalTasks = projectTasks.count
        }

        let preamble = promptCacheService.buildPreamble(context: context)
        let config = GeneratorExecutionConfig(
            llmFacade: llmFacade,
            modelId: modelId,
            backend: backend,
            preamble: preamble,
            experienceDefaultsStore: experienceDefaultsStore
        )

        for task in projectTasks {
            activityTracker.startTask(id: task.id, displayName: task.displayName)

            do {
                let content = try await projectsGenerator.execute(
                    task: task,
                    context: context,
                    config: config
                )

                reviewQueue.add(task: task, content: content)
                activityTracker.completeTask(id: task.id)
                incrementCompletedCount(for: .projects)

            } catch {
                Logger.error("Project generation failed: \(task.displayName) - \(error)", category: .ai)
                activityTracker.failTask(id: task.id, error: error.localizedDescription)
            }
        }

        updateSectionStatus(.projects, to: .completed)
    }

    // MARK: - Apply Approved Content

    func applyApprovedContent(to defaults: inout ExperienceDefaults) {
        for item in reviewQueue.approvedItems {
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
                // No edits - use original
                contentToApply = item.generatedContent
            }

            generator?.apply(content: contentToApply, to: &defaults)
        }

        Logger.info("Applied \(reviewQueue.approvedItems.count) approved items to defaults", category: .ai)
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

        case .educationDescription(let targetId, _, let courses):
            // For education, edited text is just the description
            return GeneratedContent(type: .educationDescription(targetId: targetId, description: editedText.trimmingCharacters(in: .whitespacesAndNewlines), courses: courses))

        case .objective:
            return GeneratedContent(type: .objective(summary: editedText.trimmingCharacters(in: .whitespacesAndNewlines)))

        default:
            // For types we don't handle, return original
            Logger.warning("Unhandled content type for edited content: \(originalContent.type)", category: .ai)
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

    /// Regenerate a rejected item with user feedback
    private func regenerateItem(
        itemId: UUID,
        originalContent: GeneratedContent,
        feedback: String?
    ) async -> GeneratedContent? {
        guard let context else {
            Logger.error("Cannot regenerate: no context available", category: .ai)
            return nil
        }

        // Find the original item to get its task
        guard let item = reviewQueue.item(for: itemId) else {
            Logger.error("Cannot regenerate: item not found", category: .ai)
            return nil
        }

        // Find the generator for this task
        let generatorTypeName = item.task.generatorType
        guard let generator = generators.first(where: { String(describing: type(of: $0)) == generatorTypeName }) else {
            Logger.error("Cannot regenerate: generator not found for \(generatorTypeName)", category: .ai)
            return nil
        }

        let preamble = promptCacheService.buildPreamble(context: context)
        let config = GeneratorExecutionConfig(
            llmFacade: llmFacade,
            modelId: modelId,
            backend: backend,
            preamble: preamble,
            experienceDefaultsStore: experienceDefaultsStore
        )

        do {
            let newContent = try await generator.regenerate(
                task: item.task,
                originalContent: originalContent,
                feedback: feedback,
                context: context,
                config: config
            )
            return newContent
        } catch {
            Logger.error("Regeneration failed: \(error)", category: .ai)
            return nil
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
}
