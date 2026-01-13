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
    private(set) var sectionProgress: [SectionProgress] = []

    private var isRunning = false

    // MARK: - Dependencies

    private let llmFacade: LLMFacade
    private let modelId: String
    private let promptCacheService: PromptCacheService
    private let parallelExecutor: ParallelLLMExecutor

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
        modelId: String
    ) {
        self.context = context
        self.llmFacade = llmFacade
        self.modelId = modelId
        self.promptCacheService = PromptCacheService()
        self.parallelExecutor = ParallelLLMExecutor()

        initializeSectionProgress()
    }

    private func initializeSectionProgress() {
        guard let context else { return }

        let enabledSections = context.enabledSections

        sectionProgress = enabledSections.compactMap { section in
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

        // Phase 1: Discover projects (special workflow)
        await discoverProjects(context: context)

        // Phase 2: Create tasks for all sections
        createAllTasks(context: context)

        // Phase 3: Execute tasks in parallel
        await executeAllTasks(context: context, preamble: preamble)

        isRunning = false
    }

    // MARK: - Project Discovery

    private func discoverProjects(context: SeedGenerationContext) async {
        guard let projectsGenerator = generators.first(where: { $0 is ProjectsGenerator }) as? ProjectsGenerator else {
            return
        }

        updateSectionStatus(.projects, to: .running)

        do {
            let proposals = try await projectsGenerator.discoverProjects(
                context: context,
                llmFacade: llmFacade,
                modelId: modelId
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

            let sectionTasks = generator.createTasks(context: context)
            tasks.append(contentsOf: sectionTasks)

            // Update progress tracking
            if let index = sectionProgress.firstIndex(where: { $0.section == generator.sectionKey }) {
                sectionProgress[index].totalTasks = sectionTasks.count
            }
        }
    }

    // MARK: - Task Execution

    private func executeAllTasks(context: SeedGenerationContext, preamble: String) async {
        for generator in generators {
            let sectionTasks = tasks.filter { $0.section == generator.sectionKey }

            guard !sectionTasks.isEmpty else { continue }

            updateSectionStatus(generator.sectionKey, to: .running)

            for task in sectionTasks {
                activityTracker.startTask(id: task.id, displayName: task.displayName)

                do {
                    let content = try await generator.execute(
                        task: task,
                        context: context,
                        preamble: preamble,
                        llmFacade: llmFacade,
                        modelId: modelId
                    )

                    // Handle special cases
                    if case .skillGroups(let groups) = content.type {
                        generatedSkillGroups = groups
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
        guard !approvedProposals.isEmpty else { return }

        let projectTasks = projectsGenerator.createTasks(for: approvedProposals, context: context)
        tasks.append(contentsOf: projectTasks)

        let preamble = promptCacheService.buildPreamble(context: context)

        for task in projectTasks {
            activityTracker.startTask(id: task.id, displayName: task.displayName)

            do {
                let content = try await projectsGenerator.execute(
                    task: task,
                    context: context,
                    preamble: preamble,
                    llmFacade: llmFacade,
                    modelId: modelId
                )

                reviewQueue.add(task: task, content: content)
                activityTracker.completeTask(id: task.id)

            } catch {
                Logger.error("Project generation failed: \(task.displayName) - \(error)", category: .ai)
                activityTracker.failTask(id: task.id, error: error.localizedDescription)
            }
        }
    }

    // MARK: - Apply Approved Content

    func applyApprovedContent(to defaults: inout ExperienceDefaults) {
        for item in reviewQueue.approvedItems {
            let generator = generators.first { $0.sectionKey == item.task.section }
            generator?.apply(content: item.generatedContent, to: &defaults)
        }

        Logger.info("Applied \(reviewQueue.approvedItems.count) approved items to defaults", category: .ai)
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
