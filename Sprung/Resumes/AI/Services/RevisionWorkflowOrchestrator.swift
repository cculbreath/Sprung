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
    func hideParallelReviewQueue()
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

    /// Phase 2 nodes deferred until Phase 1 review completes
    private var pendingPhase2Nodes: [ExportedReviewNode] = []
    /// Resume reference for Phase 2 continuation
    private var currentResume: Resume?
    /// CoverRefStore reference for Phase 2 continuation
    private var currentCoverRefStore: CoverRefStore?

    /// Whether Phase 2 is still pending
    var hasPhase2Pending: Bool {
        !pendingPhase2Nodes.isEmpty
    }

    /// Current phase number (1 or 2) for UI display
    private(set) var currentPhaseNumber: Int = 1
    /// Total phases (1 or 2) for UI display
    private(set) var totalPhases: Int = 1

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

        workflowState.markWorkflowStarted(.customize)
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

        Logger.info("Starting parallel workflow - Phase 1: \(phase1Nodes.count), Phase 2: \(phase2Nodes.count)")

        // Handle empty-nodes edge case
        if phase1Nodes.isEmpty && phase2Nodes.isEmpty {
            workflowState.markWorkflowCompleted(reset: true)
            return
        }

        // 5. Store Phase 2 nodes for later execution
        pendingPhase2Nodes = phase2Nodes
        currentResume = resume
        currentCoverRefStore = coverRefStore

        // 6. Set phase tracking
        currentPhaseNumber = 1
        totalPhases = (!phase1Nodes.isEmpty && !phase2Nodes.isEmpty) ? 2 : 1

        // 7. Initialize CustomizationReviewQueue and wire up regeneration callback
        let queue = CustomizationReviewQueue()
        self.reviewQueue = queue
        setupParallelRegenerationCallback()

        // 8. Execute Phase 1 (or Phase 2 directly if no Phase 1 nodes)
        if !phase1Nodes.isEmpty {
            try await executeParallelPhase(
                nodes: phase1Nodes,
                phase: 1,
                resume: resume,
                context: context,
                modelId: modelId
            )
        } else {
            // No Phase 1 nodes — execute Phase 2 directly
            currentPhaseNumber = 2
            let captured = pendingPhase2Nodes
            pendingPhase2Nodes = []
            try await executeParallelPhase(
                nodes: captured,
                phase: 2,
                resume: resume,
                context: context,
                modelId: modelId
            )
        }

        // 9. Phase execution complete — show review UI
        workflowState.setProcessingRevisions(false)
        await delegate?.showParallelReviewQueue()
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

    /// Called when the current phase review is complete — applies approved changes and advances to the next phase or finalizes.
    /// - Parameters:
    ///   - resume: The resume being customized
    ///   - context: The SwiftData model context for saving
    func completeCurrentPhaseAndAdvance(resume: Resume, context: ModelContext) async throws {
        guard let queue = reviewQueue else {
            Logger.error("No review queue available")
            return
        }

        // 1. Apply approved items to the resume tree
        let approvedItems = queue.approvedItems
        for item in approvedItems {
            applyReviewItemToResume(item, resume: resume)
        }

        Logger.info("Applied \(approvedItems.count) phase \(currentPhaseNumber) changes to resume")

        // 2. Save to SwiftData
        do {
            try context.save()
        } catch {
            Logger.error("Failed to save context after applying phase changes: \(error.localizedDescription)")
        }

        // 3. Trigger export
        exportCoordinator.debounceExport(resume: resume)

        // 4. Advance to Phase 2 if pending, otherwise finalize
        if !pendingPhase2Nodes.isEmpty {
            guard let skillStore else {
                throw RevisionWorkflowError.missingDependency("SkillStore")
            }
            guard let guidanceStore else {
                throw RevisionWorkflowError.missingDependency("InferenceGuidanceStore")
            }
            guard let modelId = workflowState.currentModelId else {
                throw RevisionWorkflowError.missingDependency("modelId")
            }
            guard let coverRefStore = currentCoverRefStore else {
                throw RevisionWorkflowError.missingDependency("CoverRefStore")
            }

            currentPhaseNumber = 2
            queue.clear()

            let captured = pendingPhase2Nodes
            pendingPhase2Nodes = []

            // Build fresh context with Phase 1 changes applied
            let customizationContext = CustomizationContext.build(
                resume: resume,
                skillStore: skillStore,
                guidanceStore: guidanceStore,
                knowledgeCardStore: knowledgeCardStore,
                coverRefStore: coverRefStore,
                applicantProfileStore: applicantProfileStore
            )

            workflowState.setProcessingRevisions(true)

            try await executeParallelPhase(
                nodes: captured,
                phase: 2,
                resume: resume,
                context: customizationContext,
                modelId: modelId
            )

            workflowState.setProcessingRevisions(false)
            await delegate?.showParallelReviewQueue()
        } else {
            finalizeWorkflow()
        }
    }

    /// Apply all approved items and close the workflow
    func applyApprovedAndClose(resume: Resume, context: ModelContext) {
        guard let queue = reviewQueue else { return }

        let approvedItems = queue.approvedItems
        for item in approvedItems {
            applyReviewItemToResume(item, resume: resume)
        }

        Logger.info("Applied \(approvedItems.count) approved changes and closing workflow")

        do {
            try context.save()
        } catch {
            Logger.error("Failed to save context after applying approved changes: \(error.localizedDescription)")
        }

        exportCoordinator.debounceExport(resume: resume)
        finalizeWorkflow()
    }

    /// Discard all changes and close the workflow
    func discardAndClose() {
        finalizeWorkflow()
    }

    /// Whether there are unapplied approved changes in the review queue
    func hasUnappliedApprovedChanges() -> Bool {
        reviewQueue?.hasApprovedItems ?? false
    }

    /// Clear all state and finalize the workflow
    private func finalizeWorkflow() {
        pendingPhase2Nodes = []
        currentResume = nil
        currentCoverRefStore = nil
        currentPhaseNumber = 1
        totalPhases = 1

        reviewQueue?.clear()
        reviewQueue = nil
        promptCacheService = nil
        parallelExecutor = nil
        taskBuilder = nil
        cachedPreamble = nil

        workflowState.setProcessingRevisions(false)
        workflowState.markWorkflowCompleted(reset: true)
        delegate?.hideParallelReviewQueue()
    }

    /// Apply a review item's changes to the resume tree
    private func applyReviewItemToResume(_ item: CustomizationReviewItem, resume: Resume) {
        guard item.shouldApplyRevision else { return }  // Skip useOriginal items

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
