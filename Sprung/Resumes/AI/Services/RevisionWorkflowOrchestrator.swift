//
//  RevisionWorkflowOrchestrator.swift
//  Sprung
//
//  Service responsible for orchestrating revision workflow execution.
//  Handles the core workflow logic for generating and resubmitting revisions.
//

import Foundation
import SwiftUI
import SwiftData

/// Protocol for receiving workflow orchestration callbacks
@MainActor
protocol RevisionWorkflowOrchestratorDelegate: AnyObject {
    func showParallelReviewQueue()
}

/// Service responsible for orchestrating revision workflow execution.
/// Coordinates LLM calls, tool execution, and revision generation.
@MainActor
@Observable
class RevisionWorkflowOrchestrator {
    // MARK: - Dependencies
    private let llm: LLMFacade
    private let openRouterService: OpenRouterService
    private let reasoningStreamManager: ReasoningStreamManager
    private let exportCoordinator: ResumeExportCoordinator
    private let streamingService: RevisionStreamingService
    private let applicantProfileStore: ApplicantProfileStore
    private let knowledgeCardStore: KnowledgeCardStore
    private let toolRunner: ToolConversationRunner
    private let phaseReviewManager: PhaseReviewManager
    private let guidanceStore: InferenceGuidanceStore?
    private let skillStore: SkillStore?
    private let titleSetStore: TitleSetStore?

    // MARK: - Parallel Workflow Components
    private var promptCacheService: CustomizationPromptCacheService?
    private var parallelExecutor: CustomizationParallelExecutor?
    private(set) var reviewQueue: CustomizationReviewQueue?
    private var taskBuilder: RevisionTaskBuilder?
    private var cachedPreamble: String?

    // MARK: - Delegate
    weak var delegate: RevisionWorkflowOrchestratorDelegate?

    // MARK: - State
    let workflowState: RevisionWorkflowState

    // MARK: - Initialization

    init(
        llm: LLMFacade,
        openRouterService: OpenRouterService,
        reasoningStreamManager: ReasoningStreamManager,
        exportCoordinator: ResumeExportCoordinator,
        streamingService: RevisionStreamingService,
        applicantProfileStore: ApplicantProfileStore,
        knowledgeCardStore: KnowledgeCardStore,
        toolRunner: ToolConversationRunner,
        phaseReviewManager: PhaseReviewManager,
        guidanceStore: InferenceGuidanceStore? = nil,
        skillStore: SkillStore? = nil,
        titleSetStore: TitleSetStore? = nil,
        workflowState: RevisionWorkflowState
    ) {
        self.llm = llm
        self.openRouterService = openRouterService
        self.reasoningStreamManager = reasoningStreamManager
        self.exportCoordinator = exportCoordinator
        self.streamingService = streamingService
        self.applicantProfileStore = applicantProfileStore
        self.knowledgeCardStore = knowledgeCardStore
        self.toolRunner = toolRunner
        self.phaseReviewManager = phaseReviewManager
        self.guidanceStore = guidanceStore
        self.skillStore = skillStore
        self.titleSetStore = titleSetStore
        self.workflowState = workflowState
    }

    // MARK: - Parallel Workflow

    /// Start the new parallel revision workflow
    /// - Parameters:
    ///   - resume: The resume to customize
    ///   - modelId: The LLM model ID (from user selection, NOT hardcoded)
    ///   - clarifyingQA: Optional clarifying questions and answers to prepend to preamble
    ///   - coverRefStore: Store for writing samples and voice primer
    func startParallelWorkflow(
        resume: Resume,
        modelId: String,
        clarifyingQA: [(ClarifyingQuestion, QuestionAnswer)]?,
        coverRefStore: CoverRefStore
    ) async throws {
        guard let skillStore else {
            Logger.error("SkillStore not configured for parallel workflow")
            throw RevisionWorkflowError.missingDependency("SkillStore")
        }

        guard let guidanceStore else {
            Logger.error("InferenceGuidanceStore not configured for parallel workflow")
            throw RevisionWorkflowError.missingDependency("InferenceGuidanceStore")
        }

        workflowState.markWorkflowStarted(.parallel)
        workflowState.setProcessingRevisions(true)
        workflowState.currentModelId = modelId

        // 1. Build CustomizationContext using the new CustomizationContext.build() method
        let context = CustomizationContext.build(
            resume: resume,
            skillStore: skillStore,
            guidanceStore: guidanceStore,
            knowledgeCardStore: knowledgeCardStore,
            coverRefStore: coverRefStore,
            applicantProfileStore: applicantProfileStore
        )

        // 2. Initialize CustomizationPromptCacheService with backend
        let cacheService = CustomizationPromptCacheService(backend: .openRouter)
        self.promptCacheService = cacheService

        // 3. If clarifyingQA exists, call promptCacheService.appendClarifyingQA()
        if let qa = clarifyingQA, !qa.isEmpty {
            cacheService.appendClarifyingQA(qa)
        }

        // 4. Get RevNodes from phaseReviewManager.buildReviewRounds() -> (phase1, phase2)
        let (phase1Nodes, phase2Nodes) = phaseReviewManager.buildReviewRounds(for: resume)

        Logger.info("🚀 Starting parallel workflow - Phase 1: \(phase1Nodes.count), Phase 2: \(phase2Nodes.count)")

        // 5. Initialize CustomizationReviewQueue and wire up regeneration callback
        let queue = CustomizationReviewQueue()
        self.reviewQueue = queue
        setupParallelRegenerationCallback()

        // 6. Phase 1 execution (if there are Phase 1 nodes)
        if !phase1Nodes.isEmpty {
            try await executeParallelPhase(
                nodes: phase1Nodes,
                phase: 1,
                resume: resume,
                context: context,
                modelId: modelId
            )
        }

        // 7. Phase 2 execution (always runs if there are Phase 2 nodes)
        if !phase2Nodes.isEmpty {
            try await executeParallelPhase(
                nodes: phase2Nodes,
                phase: 2,
                resume: resume,
                context: context,
                modelId: modelId
            )
        }

        // Show review UI via delegate
        delegate?.showParallelReviewQueue()
    }

    /// Execute a parallel phase with the given nodes
    private func executeParallelPhase(
        nodes: [ExportedReviewNode],
        phase: Int,
        resume: Resume,
        context: CustomizationContext,
        modelId: String
    ) async throws {
        guard let cacheService = promptCacheService else {
            throw RevisionWorkflowError.missingDependency("CustomizationPromptCacheService")
        }

        // Initialize task builder if needed
        if taskBuilder == nil {
            taskBuilder = RevisionTaskBuilder()
        }

        // Initialize parallel executor if needed
        if parallelExecutor == nil {
            parallelExecutor = CustomizationParallelExecutor(maxConcurrent: 5)
        }

        guard let builder = taskBuilder, let executor = parallelExecutor else {
            throw RevisionWorkflowError.missingDependency("RevisionTaskBuilder or CustomizationParallelExecutor")
        }

        // Build prompt context for cache service
        let titleSetRecords = titleSetStore?.allTitleSets ?? []
        let promptContext = CustomizationPromptContext(
            applicantProfile: context.applicantProfile,
            knowledgeCards: context.knowledgeCards,
            skills: context.skills,
            writingSamples: context.writingSamples,
            voicePrimer: context.voicePrimer,
            dossier: context.dossier,
            titleSets: titleSetRecords,
            jobApp: resume.jobApp ?? JobApp()
        )

        // Build the preamble (and cache it for regeneration)
        let preamble = cacheService.buildPreamble(context: promptContext)
        self.cachedPreamble = preamble

        // Build tasks for this phase
        let tasks = builder.buildTasks(
            from: nodes,
            resume: resume,
            jobDescription: context.jobDescription,
            skills: context.skills,
            titleSets: context.titleSets,
            phase: phase
        )

        Logger.info("📋 Phase \(phase): Built \(tasks.count) tasks")

        // Build parallel execution context
        let execContext = ParallelExecutionContext(
            jobPosting: context.jobDescription,
            resumeSnapshot: "", // Could add resume snapshot if needed
            applicantProfile: context.applicantProfile.name,
            additionalContext: ""
        )

        // Execute tasks in parallel and stream results into queue
        let stream = await executor.execute(
            tasks: tasks,
            context: execContext,
            llmFacade: llm,
            modelId: modelId,
            preamble: preamble
        )

        // Stream results into the review queue
        for await taskResult in stream {
            switch taskResult.result {
            case .success(let revision):
                // Find the matching task to create the review item
                if let task = tasks.first(where: { $0.id == taskResult.taskId }) {
                    reviewQueue?.add(task: task, revision: revision)
                    Logger.debug("✅ Added revision for: \(task.revNode.displayName)")
                }
            case .failure(let error):
                Logger.error("❌ Task failed: \(error.localizedDescription)")
            }
        }

        Logger.info("✅ Phase \(phase) execution complete: \(reviewQueue?.items.count ?? 0) items in queue")
    }

    private func setupParallelRegenerationCallback() {
        reviewQueue?.onRegenerationRequested = { [weak self] itemId, originalRevision, feedback in
            return await self?.regenerateParallelItem(
                itemId: itemId,
                originalRevision: originalRevision,
                feedback: feedback
            )
        }
    }

    private func regenerateParallelItem(
        itemId: UUID,
        originalRevision: ProposedRevisionNode,
        feedback: String?
    ) async -> ProposedRevisionNode? {
        guard let queue = reviewQueue,
              let item = queue.item(for: itemId),
              let executor = parallelExecutor,
              let preamble = cachedPreamble,
              let modelId = workflowState.currentModelId else {
            Logger.error("Missing dependencies for regeneration")
            return nil
        }

        // Build regeneration prompt with feedback
        var regenerationPrompt = item.task.taskPrompt
        if let feedback = feedback, !feedback.isEmpty {
            regenerationPrompt += "\n\n## User Feedback\nThe previous revision was rejected. Please incorporate this feedback:\n\(feedback)"
        } else {
            regenerationPrompt += "\n\n## Regeneration Request\nThe previous revision was rejected. Please try a different approach."
        }

        // Create a new task with the updated prompt
        let regenerationTask = RevisionTask(
            revNode: item.task.revNode,
            taskPrompt: regenerationPrompt,
            nodeType: item.task.nodeType,
            phase: item.task.phase
        )

        // Build a minimal context for regeneration
        let execContext = ParallelExecutionContext()

        // Execute single task via parallelExecutor.executeSingle()
        let result = await executor.executeSingle(
            task: regenerationTask,
            context: execContext,
            llmFacade: llm,
            modelId: modelId,
            preamble: preamble
        )

        switch result.result {
        case .success(let newRevision):
            Logger.info("✅ Regeneration successful for: \(item.task.revNode.displayName)")
            return newRevision
        case .failure(let error):
            Logger.error("❌ Regeneration failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Called when Phase 1 review is complete - proceeds to Phase 2
    /// - Parameters:
    ///   - resume: The resume being customized
    ///   - coverRefStore: Store for writing samples and voice primer
    func completePhase1AndStartPhase2(resume: Resume, coverRefStore: CoverRefStore) async throws {
        guard let queue = reviewQueue else {
            Logger.error("No review queue available")
            return
        }

        guard let skillStore else {
            throw RevisionWorkflowError.missingDependency("SkillStore")
        }

        guard let guidanceStore else {
            throw RevisionWorkflowError.missingDependency("InferenceGuidanceStore")
        }

        guard let modelId = workflowState.currentModelId else {
            throw RevisionWorkflowError.missingDependency("modelId")
        }

        // 1. Apply Phase 1 changes to tree
        let approvedItems = queue.approvedItems
        for item in approvedItems {
            applyReviewItemToResume(item, resume: resume)
        }

        Logger.info("✅ Applied \(approvedItems.count) Phase 1 changes to resume")

        // 2. Re-export Phase 2 nodes (now with updated context from Phase 1 changes)
        let (_, phase2Nodes) = phaseReviewManager.buildReviewRounds(for: resume)

        if phase2Nodes.isEmpty {
            Logger.info("📋 No Phase 2 nodes to process")
            workflowState.setProcessingRevisions(false)
            return
        }

        // 3. Clear the queue of Phase 1 items
        queue.clear()

        // 4. Build fresh context with Phase 1 changes applied
        let context = CustomizationContext.build(
            resume: resume,
            skillStore: skillStore,
            guidanceStore: guidanceStore,
            knowledgeCardStore: knowledgeCardStore,
            coverRefStore: coverRefStore,
            applicantProfileStore: applicantProfileStore
        )

        // 5. Execute Phase 2 in parallel
        try await executeParallelPhase(
            nodes: phase2Nodes,
            phase: 2,
            resume: resume,
            context: context,
            modelId: modelId
        )

        Logger.info("✅ Phase 2 execution complete")
    }

    /// Apply a review item's changes to the resume tree
    private func applyReviewItemToResume(_ item: CustomizationReviewItem, resume: Resume) {
        guard item.isApproved else { return }

        // Check if this is a bundled/array node
        if let sourceNodeIds = item.task.revNode.sourceNodeIds, !sourceNodeIds.isEmpty {
            applyBundledChanges(item: item, sourceNodeIds: sourceNodeIds, resume: resume)
        } else {
            // Scalar node - apply single value
            applySingleChange(item: item, resume: resume)
        }
    }

    /// Apply changes for a scalar (single value) node
    private func applySingleChange(item: CustomizationReviewItem, resume: Resume) {
        let valueToApply: String
        if let editedContent = item.editedContent {
            valueToApply = editedContent
        } else {
            valueToApply = item.revision.newValue
        }

        if let treeNode = resume.nodes.first(where: { $0.id == item.task.revNode.id }) {
            treeNode.value = valueToApply
            Logger.debug("✅ Applied scalar change to node: \(item.task.revNode.displayName)")
        } else {
            Logger.warning("⚠️ Could not find tree node: \(item.task.revNode.id)")
        }
    }

    /// Apply changes for a bundled/array node
    private func applyBundledChanges(item: CustomizationReviewItem, sourceNodeIds: [String], resume: Resume) {
        // Get the values to apply - prefer edited children, then new value array, then parse from newValue
        let valuesToApply: [String]
        if let editedChildren = item.editedChildren, !editedChildren.isEmpty {
            valuesToApply = editedChildren
        } else if let newValueArray = item.revision.newValueArray, !newValueArray.isEmpty {
            valuesToApply = newValueArray
        } else {
            // Parse from newValue string (comma or newline separated)
            valuesToApply = parseArrayFromString(item.revision.newValue)
        }

        // Apply each value to its corresponding source node
        for (index, nodeId) in sourceNodeIds.enumerated() {
            guard index < valuesToApply.count else {
                Logger.warning("⚠️ Not enough values for source node at index \(index)")
                continue
            }

            if let treeNode = resume.nodes.first(where: { $0.id == nodeId }) {
                treeNode.value = valuesToApply[index]
                Logger.debug("✅ Applied array value to node \(index): \(nodeId)")
            } else {
                Logger.warning("⚠️ Could not find source tree node: \(nodeId)")
            }
        }

        Logger.info("✅ Applied bundled changes (\(valuesToApply.count) values) for: \(item.task.revNode.displayName)")
    }

    /// Parse array values from a string (handles comma-separated or newline-separated lists)
    private func parseArrayFromString(_ text: String) -> [String] {
        // Try newline-separated first (for bullet lists)
        let lines = text.components(separatedBy: .newlines)
            .map { line in
                // Remove bullet points, dashes, numbers
                line.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "^[•\\-\\*\\d\\.\\)]+\\s*", with: "", options: .regularExpression)
            }
            .filter { !$0.isEmpty }

        if lines.count > 1 {
            return lines
        }

        // Fall back to comma-separated
        return text.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Workflow Errors

enum RevisionWorkflowError: LocalizedError {
    case missingDependency(String)

    var errorDescription: String? {
        switch self {
        case .missingDependency(let name):
            return "Missing required dependency: \(name)"
        }
    }
}
