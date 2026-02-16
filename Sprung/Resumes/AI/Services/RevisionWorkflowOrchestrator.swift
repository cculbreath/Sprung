//
//  RevisionWorkflowOrchestrator.swift
//  Sprung
//
//  Service responsible for orchestrating revision workflow execution.
//  Handles the core workflow logic for generating and resubmitting revisions.
//  Integrates targeting plan generation, compound calls, and Phase 1->2 forwarding.
//

import Foundation
import SwiftUI
import SwiftData

/// Protocol for receiving workflow orchestration callbacks
@MainActor
protocol RevisionWorkflowOrchestratorDelegate: AnyObject {
    func showParallelReviewQueue()
    func hideParallelReviewQueue()
    func showCoherenceReport()
    func hideCoherenceReport()
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
    private let targetingPlanService: TargetingPlanService
    private let coherencePassService: CoherencePassService
    private let candidateDossierStore: CandidateDossierStore?

    // MARK: - Parallel Workflow Components
    private var promptCacheService: CustomizationPromptCacheService?
    private var parallelExecutor: CustomizationParallelExecutor?
    private(set) var reviewQueue: CustomizationReviewQueue?
    private var taskBuilder: RevisionTaskBuilder?
    private var cachedPreamble: String?
    /// Core preamble (system message) cached for regeneration — identical across all tasks
    private var cachedCorePreamble: String?
    private var cachedToolConfig: ToolConfiguration?

    /// Resume reference for workflow continuation
    private var currentResume: Resume?
    /// CoverRefStore reference for workflow continuation
    private var currentCoverRefStore: CoverRefStore?
    /// Cached targeting plan for the entire workflow
    private var cachedTargetingPlan: TargetingPlan?
    /// Auto pre-step decisions context for review tasks
    private var autoDecisionsContext: String?
    /// Cached customization context
    private var cachedContext: CustomizationContext?
    /// Reasoning config for extended thinking (nil when reasoning is off)
    private var cachedReasoning: OpenRouterReasoning?

    /// Count of fields customized (for coherence threshold)
    private var totalCustomizedFieldCount: Int = 0

    // MARK: - Coherence Pass State

    /// The most recent coherence report (nil until the pass runs).
    private(set) var coherenceReport: CoherenceReport?

    /// Whether the coherence pass is currently running.
    private(set) var isRunningCoherencePass: Bool = false

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
        targetingPlanService: TargetingPlanService,
        coherencePassService: CoherencePassService,
        candidateDossierStore: CandidateDossierStore? = nil,
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
        self.targetingPlanService = targetingPlanService
        self.coherencePassService = coherencePassService
        self.candidateDossierStore = candidateDossierStore
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

        // 0. Clear stale state from any previous run
        resetWorkflowState()

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
            applicantProfileStore: applicantProfileStore,
            candidateDossierStore: candidateDossierStore
        )
        self.cachedContext = context

        // 2. Initialize CustomizationPromptCacheService with inferred backend
        let cacheService = CustomizationPromptCacheService(backend: .infer(from: modelId))
        self.promptCacheService = cacheService

        // 3. If clarifyingQA exists, call promptCacheService.appendClarifyingQA()
        if let qa = clarifyingQA, !qa.isEmpty {
            cacheService.appendClarifyingQA(qa)
        }

        // 4. Build reasoning config from user setting
        let reasoningEffortRaw = UserDefaults.standard.integer(forKey: "customizationReasoningEffort")
        let reasoningLevel = DebugSettingsStore.ReasoningEffortLevel(rawValue: reasoningEffortRaw) ?? .off
        if let effortString = reasoningLevel.effortString {
            self.cachedReasoning = OpenRouterReasoning(effort: effortString, includeReasoning: true)
            Logger.info("[Orchestrator] Reasoning enabled: effort=\(effortString)", category: .ai)
        } else {
            self.cachedReasoning = nil
        }

        // 5. Generate TargetingPlan via TargetingPlanService
        Logger.info("Generating strategic targeting plan...", category: .ai)
        if cachedReasoning != nil {
            reasoningStreamManager.startReasoning(modelName: modelId)
        }
        let targetingPlan = try await targetingPlanService.generateTargetingPlan(
            context: context,
            llmFacade: llm,
            modelId: modelId,
            reasoning: cachedReasoning,
            reasoningStreamManager: cachedReasoning != nil ? reasoningStreamManager : nil
        )
        if cachedReasoning != nil {
            reasoningStreamManager.stopStream()
        }
        self.cachedTargetingPlan = targetingPlan
        Logger.info("Targeting plan generated: \(targetingPlan.emphasisThemes.count) themes, \(targetingPlan.workEntryGuidance.count) work entries", category: .ai)

        // 5. Get review manifest: auto-apply nodes + human review nodes
        let (autoNodes, reviewNodes) = phaseReviewManager.buildReviewManifest(for: resume)

        Logger.info("Starting parallel workflow - Auto: \(autoNodes.count), Review: \(reviewNodes.count)")

        // Handle empty-nodes edge case
        if autoNodes.isEmpty && reviewNodes.isEmpty {
            workflowState.markWorkflowCompleted(reset: true)
            return
        }

        currentResume = resume
        currentCoverRefStore = coverRefStore

        // 6. Initialize CustomizationReviewQueue and wire up regeneration callbacks
        let queue = CustomizationReviewQueue()
        self.reviewQueue = queue
        setupParallelRegenerationCallback()
        setupCompoundRegenerationCallback()

        // 7. Execute auto pre-step (skill categories, titles) — auto-apply results
        if !autoNodes.isEmpty {
            let autoDecisions = try await executeAutoPreStep(
                nodes: autoNodes,
                resume: resume,
                context: context,
                modelId: modelId
            )
            self.autoDecisionsContext = autoDecisions
            Logger.info("Auto pre-step complete: \(autoDecisions.count) chars of decisions context", category: .ai)
        }

        // 8. Execute all review tasks in parallel
        var totalTasksAttempted = 0
        if !reviewNodes.isEmpty {
            totalTasksAttempted += try await executeParallelPhase(
                nodes: reviewNodes,
                phase: 1,
                resume: resume,
                context: context,
                modelId: modelId
            )
        }

        // 9. If no review items produced, all tasks failed — surface error
        if let queue = reviewQueue, queue.activeItems.isEmpty && totalTasksAttempted > 0 {
            Logger.error("All \(totalTasksAttempted) tasks failed — no review items produced")
            workflowState.setProcessingRevisions(false)
            workflowState.markWorkflowCompleted(reset: true)
            throw RevisionWorkflowError.allTasksFailed(taskCount: totalTasksAttempted, phase: 1)
        }

        // 10. Show single review pass UI
        workflowState.setProcessingRevisions(false)
        await delegate?.showParallelReviewQueue()
    }

    /// Execute a parallel phase with the given nodes. Returns the number of tasks attempted.
    @discardableResult
    private func executeParallelPhase(
        nodes: [ExportedReviewNode],
        phase: Int,
        resume: Resume,
        context: CustomizationContext,
        modelId: String
    ) async throws -> Int {
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
            allCards: context.allCards,
            relevantCardIds: context.relevantCardIds,
            skills: context.skills,
            writersVoice: context.writersVoice,
            dossier: context.dossier,
            titleSets: titleSetRecords,
            jobApp: resume.jobApp ?? JobApp()
        )

        // Build split preamble: core (system message, cacheable) + variable (user message, per-task)
        let variableContext = buildAndCachePreamble(context: promptContext)

        // Build text resume snapshot for cross-section context
        let textResumeSnapshot = ResumeTextSnapshotBuilder.buildSnapshot(resume: resume)

        // Build tasks for this phase with targeting plan and Phase 1 decisions
        let tasks = builder.buildTasks(
            from: nodes,
            context: context,
            phase: phase,
            targetingPlan: cachedTargetingPlan,
            phase1Decisions: autoDecisionsContext,
            textResumeSnapshot: textResumeSnapshot
        )

        Logger.info("Phase \(phase): Built \(tasks.count) tasks (compound grouping may reduce from \(nodes.count) nodes)", category: .ai)

        // Build tool configuration if tools are enabled and model supports them
        let toolConfig = buildToolConfiguration(modelId: modelId, resume: resume)
        self.cachedToolConfig = toolConfig

        // Clear reasoning state from targeting plan phase before parallel execution
        clearReasoningStateIfNeeded()

        // Build reasoning callback for parallel tasks — route each task's
        // reasoning into its own section so parallel streams don't interleave.
        let reasoning = cachedReasoning
        let streamManager = reasoningStreamManager
        let reasoningCallback: (@Sendable (UUID, String) async -> Void)?
        if reasoning != nil {
            let taskNames = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.revNode.displayName) })
            reasoningCallback = { taskId, text in
                let name = taskNames[taskId] ?? "Task"
                await streamManager.appendReasoning(text, taskId: taskId, taskName: name)
            }
        } else {
            reasoningCallback = nil
        }

        // Execute tasks in parallel and stream results into queue.
        // Core preamble goes to system message (cacheable), variable context to user message.
        let stream = await executor.execute(
            tasks: tasks,
            llmFacade: llm,
            modelId: modelId,
            preamble: variableContext,
            systemPrompt: cachedCorePreamble,
            toolConfig: toolConfig,
            reasoning: reasoning,
            onReasoningChunk: reasoningCallback
        )

        // Stream results into the review queue
        for await taskResult in stream {
            switch taskResult.result {
            case .success(let revision):
                // Find the matching task to create the review item
                if let task = tasks.first(where: { $0.id == taskResult.taskId }) {
                    if task.nodeType == .compound, let compoundResults = taskResult.compoundResults {
                        // Compound task: split into individual review items
                        let originalNodes = resolveOriginalNodes(for: task, from: nodes)
                        reviewQueue?.addCompoundGroup(
                            compoundTask: task,
                            revisions: compoundResults,
                            originalNodes: originalNodes
                        )
                        Logger.debug("Added compound group for: \(task.revNode.displayName) (\(compoundResults.count) fields)", category: .ai)
                    } else {
                        reviewQueue?.add(task: task, revision: revision)
                        Logger.debug("Added revision for: \(task.revNode.displayName)", category: .ai)
                    }
                }
            case .failure(let error):
                let taskName = tasks.first(where: { $0.id == taskResult.taskId })?.revNode.displayName ?? "unknown"
                Logger.error("Task '\(taskName)' failed after retries: \(error.localizedDescription)", category: .ai)
            }
        }

        Logger.info("Phase \(phase) execution complete: \(reviewQueue?.items.count ?? 0) items in queue", category: .ai)
        return tasks.count
    }

    /// Execute auto pre-step nodes (skill categories, titles), auto-apply results,
    /// and return a decisions context string for downstream review tasks.
    private func executeAutoPreStep(
        nodes: [ExportedReviewNode],
        resume: Resume,
        context: CustomizationContext,
        modelId: String
    ) async throws -> String {
        guard let cacheService = promptCacheService else {
            throw RevisionWorkflowError.missingDependency("CustomizationPromptCacheService")
        }

        if taskBuilder == nil { taskBuilder = RevisionTaskBuilder() }
        if parallelExecutor == nil { parallelExecutor = CustomizationParallelExecutor(maxConcurrent: 5) }

        guard let builder = taskBuilder, let executor = parallelExecutor else {
            throw RevisionWorkflowError.missingDependency("RevisionTaskBuilder or CustomizationParallelExecutor")
        }

        let titleSetRecords = titleSetStore?.allTitleSets ?? []
        let promptContext = CustomizationPromptContext(
            applicantProfile: context.applicantProfile,
            knowledgeCards: context.knowledgeCards,
            allCards: context.allCards,
            relevantCardIds: context.relevantCardIds,
            skills: context.skills,
            writersVoice: context.writersVoice,
            dossier: context.dossier,
            titleSets: titleSetRecords,
            jobApp: resume.jobApp ?? JobApp()
        )

        // Build split preamble: core (system message) + variable (user message)
        let variableContext = buildAndCachePreamble(context: promptContext)

        let textResumeSnapshot = ResumeTextSnapshotBuilder.buildSnapshot(resume: resume)

        let tasks = builder.buildTasks(
            from: nodes,
            context: context,
            phase: 1,
            targetingPlan: cachedTargetingPlan,
            textResumeSnapshot: textResumeSnapshot
        )

        Logger.info("Auto pre-step: executing \(tasks.count) tasks", category: .ai)

        // Clear reasoning state before parallel execution
        clearReasoningStateIfNeeded()

        // Execute and collect results with split preamble
        let results = await executor.executeAll(
            tasks: tasks,
            llmFacade: llm,
            modelId: modelId,
            preamble: variableContext,
            systemPrompt: cachedCorePreamble,
            reasoning: cachedReasoning
        )

        // Build synthetic review items from results and auto-apply
        var autoAppliedItems: [CustomizationReviewItem] = []
        for task in tasks {
            guard let result = results[task.id] else { continue }
            switch result {
            case .success(let revision):
                var item = CustomizationReviewItem(task: task, revision: revision)
                item.userAction = .approved
                autoAppliedItems.append(item)
            case .failure(let error):
                Logger.warning("Auto pre-step task '\(task.revNode.displayName)' failed: \(error.localizedDescription)", category: .ai)
            }
        }

        // Apply to resume tree
        if let modelContext = currentResume?.modelContext {
            for item in autoAppliedItems {
                applyReviewItemToResume(item, resume: resume, context: modelContext)
            }
            totalCustomizedFieldCount += autoAppliedItems.count

            do {
                try modelContext.save()
            } catch {
                Logger.error("Failed to save auto pre-step changes: \(error.localizedDescription)")
            }
            exportCoordinator.debounceExport(resume: resume)
        }

        Logger.info("Auto pre-step: applied \(autoAppliedItems.count) changes", category: .ai)

        // Build decisions context string
        return RevisionTaskBuilder.buildPhase1DecisionsContext(from: autoAppliedItems)
    }

    /// Resolve original ExportedReviewNodes for a compound task's source node IDs.
    private func resolveOriginalNodes(for task: RevisionTask, from allNodes: [ExportedReviewNode]) -> [ExportedReviewNode] {
        guard let sourceIds = task.revNode.sourceNodeIds else { return [] }
        return sourceIds.compactMap { sourceId in
            allNodes.first { $0.id == sourceId }
        }
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

    private func setupCompoundRegenerationCallback() {
        reviewQueue?.onCompoundRegenerationRequested = { [weak self] groupId, feedback in
            return await self?.regenerateCompoundGroup(groupId: groupId, feedback: feedback)
        }
    }

    /// Build a prompt section describing previous rejected attempts so the LLM avoids repeating them.
    private func buildRejectionHistorySection(
        history: [RejectionRecord],
        currentFeedback: String?
    ) -> String {
        // Build the current rejection record inline (not yet stored in history)
        // History contains all *prior* rejections; current feedback is for the attempt being rejected now.
        var section = "\n\n## Previous Rejected Attempts\n\n"
        section += "This field has been revised \(history.count) time(s) already, and each attempt was rejected. "
        section += "Below is the full history of what was proposed and why the user rejected it.\n\n"
        section += "**How to use this history:**\n"
        section += "1. Read the user feedback across all attempts to understand what they want changed — it may be a small tweak or a larger shift in direction.\n"
        section += "2. When feedback is specific (e.g., \"too formal\" or \"wrong skills\"), address that specific issue while preserving what worked.\n"
        section += "3. When feedback is absent, the overall approach was unsuitable — try a meaningfully different angle.\n"
        section += "4. Never produce output identical or near-identical to a previous attempt. Each revision must visibly incorporate the feedback.\n"

        for (index, record) in history.enumerated() {
            section += "\n### Attempt \(index + 1)\n"
            if let array = record.proposedValueArray, !array.isEmpty {
                section += "**Proposed:** \(array.joined(separator: "; "))\n"
            } else {
                section += "**Proposed:** \(record.proposedValue)\n"
            }
            if !record.reasoning.isEmpty {
                section += "**Your reasoning at the time:** \(record.reasoning)\n"
            }
            if let feedback = record.userFeedback, !feedback.isEmpty {
                section += "**Why it was rejected:** \(feedback)\n"
            } else {
                section += "**Why it was rejected:** (No specific feedback — the user found the overall approach unsuitable)\n"
            }
        }

        // Add the current feedback as actionable guidance
        if let feedback = currentFeedback, !feedback.isEmpty {
            section += "\n## Direction for This Attempt\n\n"
            section += "The user provided this guidance for what they want instead:\n\(feedback)"
        }

        return section
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

        // Build regeneration prompt with full rejection history
        var regenerationPrompt = item.task.taskPrompt

        // Build current rejection record to include alongside prior history
        let currentRecord = RejectionRecord(
            proposedValue: item.revision.newValue,
            proposedValueArray: item.revision.newValueArray,
            reasoning: item.revision.why,
            userFeedback: feedback
        )
        let fullHistory = item.rejectionHistory + [currentRecord]
        regenerationPrompt += buildRejectionHistorySection(history: fullHistory, currentFeedback: feedback)

        // Create a new task with the updated prompt
        let regenerationTask = RevisionTask(
            revNode: item.task.revNode,
            taskPrompt: regenerationPrompt,
            nodeType: item.task.nodeType,
            phase: item.task.phase
        )

        // Build reasoning callback for regeneration
        let reasoning = cachedReasoning
        let streamManager = reasoningStreamManager
        let reasoningCallback: (@Sendable (UUID, String) async -> Void)?
        if reasoning != nil {
            reasoningCallback = { _, text in
                await streamManager.appendReasoning(text)
            }
        } else {
            reasoningCallback = nil
        }

        // Execute single task via parallelExecutor.executeSingle()
        let result = await executor.executeSingle(
            task: regenerationTask,
            llmFacade: llm,
            modelId: modelId,
            preamble: preamble,
            systemPrompt: cachedCorePreamble,
            toolConfig: cachedToolConfig,
            reasoning: reasoning,
            onReasoningChunk: reasoningCallback
        )

        switch result.result {
        case .success(let newRevision):
            Logger.info("Regeneration successful for: \(item.task.revNode.displayName)", category: .ai)
            return newRevision
        case .failure(let error):
            Logger.error("Regeneration failed: \(error.localizedDescription)", category: .ai)
            return nil
        }
    }

    /// Regenerate an entire compound group.
    private func regenerateCompoundGroup(groupId: String, feedback: String?) async -> [ProposedRevisionNode]? {
        guard let queue = reviewQueue,
              let executor = parallelExecutor,
              let preamble = cachedPreamble,
              let modelId = workflowState.currentModelId,
              let builder = taskBuilder,
              let context = cachedContext else {
            Logger.error("Missing dependencies for compound regeneration")
            return nil
        }

        // Get the group items to determine which nodes to regenerate
        let groupItems = queue.itemsInCompoundGroup(groupId)
        guard !groupItems.isEmpty else { return nil }

        // Rebuild the compound task from the original nodes
        let originalNodes = groupItems.map { $0.task.revNode }

        guard let resume = currentResume else {
            Logger.error("No resume available for compound regeneration")
            return nil
        }

        // Build text resume snapshot for cross-section context
        let textResumeSnapshot = ResumeTextSnapshotBuilder.buildSnapshot(resume: resume)

        // Rebuild as compound tasks (should produce 1 compound task from the group)
        let tasks = builder.buildTasks(
            from: originalNodes,
            context: context,
            phase: groupItems[0].task.phase,
            targetingPlan: cachedTargetingPlan,
            phase1Decisions: autoDecisionsContext,
            textResumeSnapshot: textResumeSnapshot
        )

        // Find the compound task
        guard let compoundTask = tasks.first(where: { $0.nodeType == .compound }) else {
            Logger.error("Failed to rebuild compound task for group: \(groupId)")
            return nil
        }

        // Use the longest rejection history from any group item (all items are
        // rejected together, but histories may diverge if items were added at
        // different times)
        let compoundHistory = groupItems.max(by: { $0.rejectionHistory.count < $1.rejectionHistory.count })?.rejectionHistory ?? []

        // Build a combined current rejection record from all group fields
        let combinedProposed = groupItems.map { "\($0.task.revNode.displayName): \($0.revision.newValue)" }.joined(separator: "\n")
        let combinedReasoning = groupItems.compactMap { $0.revision.why.isEmpty ? nil : "\($0.task.revNode.displayName): \($0.revision.why)" }.joined(separator: "\n")
        let currentRecord = RejectionRecord(
            proposedValue: combinedProposed,
            proposedValueArray: nil,
            reasoning: combinedReasoning,
            userFeedback: feedback
        )
        let fullHistory = compoundHistory + [currentRecord]

        // Add rejection history to prompt
        var regenerationPrompt = compoundTask.taskPrompt
        regenerationPrompt += buildRejectionHistorySection(history: fullHistory, currentFeedback: feedback)

        let regenerationTask = RevisionTask(
            revNode: compoundTask.revNode,
            taskPrompt: regenerationPrompt,
            nodeType: .compound,
            phase: compoundTask.phase
        )

        // Build reasoning callback for compound regeneration
        let reasoning = cachedReasoning
        let streamManager = reasoningStreamManager
        let reasoningCallback: (@Sendable (UUID, String) async -> Void)?
        if reasoning != nil {
            reasoningCallback = { _, text in
                await streamManager.appendReasoning(text)
            }
        } else {
            reasoningCallback = nil
        }

        let result = await executor.executeSingle(
            task: regenerationTask,
            llmFacade: llm,
            modelId: modelId,
            preamble: preamble,
            systemPrompt: cachedCorePreamble,
            toolConfig: cachedToolConfig,
            reasoning: reasoning,
            onReasoningChunk: reasoningCallback
        )

        switch result.result {
        case .success:
            if let compoundResults = result.compoundResults {
                Logger.info("Compound regeneration successful for group: \(groupId) (\(compoundResults.count) fields)", category: .ai)
                return compoundResults
            }
            // Single result fallback
            if case .success(let single) = result.result {
                return [single]
            }
            return nil
        case .failure(let error):
            Logger.error("Compound regeneration failed: \(error.localizedDescription)", category: .ai)
            return nil
        }
    }

    /// Called when review is complete — applies approved changes and runs coherence pass or finalizes.
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
            applyReviewItemToResume(item, resume: resume, context: context)
        }

        // Track total customized fields for coherence threshold
        let appliedCount = approvedItems.filter { $0.shouldApplyRevision }.count
        totalCustomizedFieldCount += appliedCount

        Logger.info("Applied \(approvedItems.count) review changes to resume")

        // 2. Save to SwiftData
        do {
            try context.save()
        } catch {
            Logger.error("Failed to save context after applying changes: \(error.localizedDescription)")
        }

        // 3. Trigger export
        exportCoordinator.debounceExport(resume: resume)

        // 4. Run coherence pass if warranted, otherwise finalize
        await runCoherencePassIfNeeded(resume: resume)
    }

    /// Apply all approved items and close the workflow
    func applyApprovedAndClose(resume: Resume, context: ModelContext) {
        guard let queue = reviewQueue else {
            Logger.error("No review queue available for apply", category: .ai)
            return
        }

        let approvedItems = queue.approvedItems
        for item in approvedItems {
            applyReviewItemToResume(item, resume: resume, context: context)
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

    // MARK: - Coherence Pass

    /// Called by the UI when the user finishes reviewing the coherence report.
    func completeCoherencePass() {
        coherenceReport = nil
        delegate?.hideCoherenceReport()
        finalizeWorkflow()
    }

    /// Called by the UI when the user wants to skip the coherence report entirely.
    func skipCoherencePass() {
        coherenceReport = nil
        delegate?.hideCoherenceReport()
        finalizeWorkflow()
    }

    /// Run the coherence pass if enough fields were customized and the user hasn't opted out.
    private func runCoherencePassIfNeeded(resume: Resume) async {
        // Check opt-out flag
        let coherenceEnabled = UserDefaults.standard.bool(forKey: "enableCoherencePass")
        guard coherenceEnabled else {
            Logger.info("[CoherencePass] Skipped (disabled in settings)")
            finalizeWorkflow()
            return
        }

        // Check minimum threshold
        guard totalCustomizedFieldCount >= CoherencePassService.minimumFieldsForCoherenceCheck else {
            Logger.info("[CoherencePass] Skipped (only \(totalCustomizedFieldCount) fields customized, need \(CoherencePassService.minimumFieldsForCoherenceCheck))")
            finalizeWorkflow()
            return
        }

        guard let modelId = workflowState.currentModelId else {
            Logger.warning("[CoherencePass] No model ID available, skipping")
            finalizeWorkflow()
            return
        }

        isRunningCoherencePass = true
        workflowState.setProcessingRevisions(true)

        do {
            let report = try await coherencePassService.runCoherenceCheck(
                resume: resume,
                targetingPlan: cachedTargetingPlan,
                jobDescription: cachedContext?.jobDescription ?? "",
                llmFacade: llm,
                modelId: modelId
            )

            isRunningCoherencePass = false
            workflowState.setProcessingRevisions(false)
            coherenceReport = report

            Logger.info("[CoherencePass] Report ready: \(report.overallCoherence.rawValue), \(report.issues.count) issues")
            delegate?.showCoherenceReport()
        } catch {
            Logger.error("[CoherencePass] Failed: \(error.localizedDescription)")
            isRunningCoherencePass = false
            workflowState.setProcessingRevisions(false)
            finalizeWorkflow()
        }
    }

    /// Reset all cached/stale state at the start of a new workflow run.
    /// Prevents leakage of previous run's decisions, targeting plan, preamble, etc.
    private func resetWorkflowState() {
        currentResume = nil
        currentCoverRefStore = nil
        cachedTargetingPlan = nil
        autoDecisionsContext = nil
        cachedContext = nil
        cachedReasoning = nil
        totalCustomizedFieldCount = 0
        coherenceReport = nil
        isRunningCoherencePass = false

        reviewQueue?.clear()
        reviewQueue = nil
        promptCacheService = nil
        parallelExecutor = nil
        taskBuilder = nil
        cachedPreamble = nil
        cachedCorePreamble = nil
        cachedToolConfig = nil
    }

    /// Clear all state and finalize the workflow
    private func finalizeWorkflow() {
        resetWorkflowState()
        workflowState.setProcessingRevisions(false)
        workflowState.markWorkflowCompleted(reset: true)
        delegate?.hideParallelReviewQueue()
    }

    // MARK: - Preamble Building

    /// Build and cache the split preamble (core system prompt + variable user context).
    /// Returns the variable context string for use in user messages.
    @discardableResult
    private func buildAndCachePreamble(context: CustomizationPromptContext) -> String {
        guard let cacheService = promptCacheService else {
            Logger.error("No prompt cache service available", category: .ai)
            return ""
        }
        let corePreamble = cacheService.buildCorePreamble(context: context)
        let variableContext = cacheService.buildVariableContext(context: context)
        self.cachedCorePreamble = corePreamble
        self.cachedPreamble = corePreamble + "\n\n---\n\n" + variableContext
        return variableContext
    }

    /// Clear reasoning state before starting a new parallel execution phase.
    private func clearReasoningStateIfNeeded() {
        if cachedReasoning != nil {
            reasoningStreamManager.clear()
            reasoningStreamManager.isVisible = false
        }
    }

    // MARK: - Tool Configuration

    /// Build a ToolConfiguration for the parallel executor if tools are enabled
    /// and the selected model supports tool calling. Returns nil if tools should not be used.
    private func buildToolConfiguration(modelId: String, resume: Resume) -> ToolConfiguration? {
        // Check feature flag
        let toolsEnabled = UserDefaults.standard.bool(forKey: "enableResumeCustomizationTools")
        guard toolsEnabled else {
            Logger.debug("[Orchestrator] Tool feature flag disabled", category: .ai)
            return nil
        }

        // Check model tool support
        let model = openRouterService.findModel(id: modelId)
        let supportsTools = model?.supportsTools ?? false
        guard supportsTools else {
            Logger.debug("[Orchestrator] Model \(modelId) does not support tools", category: .ai)
            return nil
        }

        // Build the tool registry and definitions
        let registry = ResumeToolRegistry(knowledgeCardStore: knowledgeCardStore)
        let tools = registry.buildChatTools()

        guard !tools.isEmpty else {
            Logger.debug("[Orchestrator] No tools registered", category: .ai)
            return nil
        }

        Logger.info("[Orchestrator] Enabling tool use with \(tools.count) tools for parallel execution", category: .ai)

        // Capture the registry and resume for the execution closure.
        // The closure bridges from the non-isolated actor context to @MainActor
        // for tool execution.
        let jobApp = resume.jobApp
        let toolConfig = ToolConfiguration(
            tools: tools,
            executeTool: { @Sendable toolName, toolArguments in
                let context = ResumeToolContext(
                    resume: resume,
                    jobApp: jobApp
                )
                let result = try await registry.executeTool(
                    name: toolName,
                    arguments: toolArguments,
                    context: context
                )
                switch result {
                case .immediate(let json):
                    return json.rawString() ?? "{}"
                case .error(let errorMessage):
                    return "{\"error\": \"\(errorMessage)\"}"
                }
            }
        )

        return toolConfig
    }

    /// Apply a review item's changes to the resume tree
    private func applyReviewItemToResume(_ item: CustomizationReviewItem, resume: Resume, context: ModelContext) {
        guard item.shouldApplyRevision else { return }  // Skip useOriginal items

        // Check if this is a serialized object bundle (multi-attribute section)
        if item.task.revNode.id.hasSuffix("-object"),
           let sourceNodeIds = item.task.revNode.sourceNodeIds, !sourceNodeIds.isEmpty {
            applySerializedObjectChanges(item: item, sourceNodeIds: sourceNodeIds, resume: resume, context: context)
        } else if let sourceNodeIds = item.task.revNode.sourceNodeIds, !sourceNodeIds.isEmpty {
            applyBundledChanges(item: item, sourceNodeIds: sourceNodeIds, resume: resume, context: context)
        } else {
            applySingleChange(item: item, resume: resume, context: context)
        }
    }

    /// Apply changes for a single (non-bundled) node.
    /// Handles both scalar leaf nodes and container nodes with children.
    private func applySingleChange(item: CustomizationReviewItem, resume: Resume, context: ModelContext) {
        guard let treeNode = resume.nodes.first(where: { $0.id == item.task.revNode.id }) else {
            Logger.warning("Could not find tree node: \(item.task.revNode.id)")
            return
        }

        // Container node (e.g., keywords with child entries): replace children
        if !treeNode.orderedChildren.isEmpty {
            let childValues: [String]
            if let editedChildren = item.editedChildren, !editedChildren.isEmpty {
                childValues = editedChildren
            } else if let newArray = item.revision.newValueArray, !newArray.isEmpty {
                childValues = newArray
            } else if let editedContent = item.editedContent, !editedContent.isEmpty {
                childValues = parseArrayFromString(editedContent)
            } else {
                childValues = parseArrayFromString(item.revision.newValue)
            }
            overwriteContainerChildren(container: treeNode, newValues: childValues, context: context)
            Logger.debug("Applied \(childValues.count) children to container node: \(item.task.revNode.displayName)")
            return
        }

        // Scalar leaf node: set value directly
        let valueToApply: String
        if let editedContent = item.editedContent {
            valueToApply = editedContent
        } else if let editedChildren = item.editedChildren, !editedChildren.isEmpty {
            // Defensive: array edit on a scalar item — join into single value
            valueToApply = editedChildren.joined(separator: ", ")
        } else {
            valueToApply = item.revision.newValue
        }

        treeNode.value = valueToApply
        // Sync parent entry name when updating a "name" field
        if treeNode.name == "name", let parent = treeNode.parent {
            parent.name = valueToApply
        }
        Logger.debug("Applied scalar change to node: \(item.task.revNode.displayName)")
    }

    /// Apply changes for a bundled/array node.
    /// Each entry in valuesToApply maps 1:1 to a sourceNodeId.
    /// For scalar source nodes, the value is written directly.
    /// For container source nodes, the value is parsed and the children are overwritten.
    private func applyBundledChanges(item: CustomizationReviewItem, sourceNodeIds: [String], resume: Resume, context: ModelContext) {
        // Get the values to apply - prefer edited children, then edited content parsed as array,
        // then new value array, then parse from newValue
        let valuesToApply: [String]
        if let editedChildren = item.editedChildren, !editedChildren.isEmpty {
            valuesToApply = editedChildren
        } else if let editedContent = item.editedContent, !editedContent.isEmpty {
            // Defensive: scalar edit on a bundled item — parse into array
            valuesToApply = parseArrayFromString(editedContent)
        } else if let newValueArray = item.revision.newValueArray, !newValueArray.isEmpty {
            valuesToApply = newValueArray
        } else {
            // Parse from newValue string (comma or newline separated)
            valuesToApply = parseArrayFromString(item.revision.newValue)
        }

        // Apply each value to its corresponding source node
        for (index, nodeId) in sourceNodeIds.enumerated() {
            guard index < valuesToApply.count else {
                Logger.warning("Not enough values for source node at index \(index)")
                continue
            }

            guard let treeNode = resume.nodes.first(where: { $0.id == nodeId }) else {
                Logger.warning("Could not find source tree node: \(nodeId)")
                continue
            }

            if treeNode.orderedChildren.isEmpty {
                // Scalar node: set value directly
                treeNode.value = valuesToApply[index]
                // Sync parent entry name when updating a "name" field
                if treeNode.name == "name", let parent = treeNode.parent {
                    parent.name = valuesToApply[index]
                }
                Logger.debug("Applied scalar value to node \(index): \(nodeId)")
            } else {
                // Container node: parse the value into individual entries and overwrite children
                let childValues = parseArrayFromString(valuesToApply[index])
                overwriteContainerChildren(container: treeNode, newValues: childValues, context: context)
                Logger.debug("Applied \(childValues.count) children to container node \(index): \(nodeId)")
            }
        }

        Logger.info("Applied bundled changes (\(valuesToApply.count) values) for: \(item.task.revNode.displayName)")
    }

    /// Cached regex for stripping bullet/number prefixes from list items
    private static let bulletPrefixPattern = try! NSRegularExpression(pattern: "^[•\\-\\*\\d\\.\\)]+\\s*")

    /// Parse array values from a string (handles comma-separated or newline-separated lists)
    private func parseArrayFromString(_ text: String) -> [String] {
        // Try newline-separated first (for bullet lists)
        let lines = text.components(separatedBy: .newlines)
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let range = NSRange(trimmed.startIndex..., in: trimmed)
                return Self.bulletPrefixPattern.stringByReplacingMatches(in: trimmed, range: range, withTemplate: "")
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

    /// Apply changes from a serialized object bundle (multi-attribute section).
    ///
    /// The `newValue` is a JSON array of entry objects (e.g., `[{"name": "...", "keywords": [...]}, ...]`).
    /// `sourceNodeIds` are ordered: for each entry, one ID per attribute in the original attribute order.
    /// So for N entries × M attributes: sourceNodeIds[i * M + j] = entry i's attribute j's tree node ID.
    ///
    /// Attribute order is encoded in the revNode path: `section.*.(attr1, attr2)`.
    private func applySerializedObjectChanges(
        item: CustomizationReviewItem,
        sourceNodeIds: [String],
        resume: Resume,
        context: ModelContext
    ) {
        let jsonString = item.editedContent ?? item.revision.newValue
        guard let jsonData = jsonString.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            Logger.warning("Failed to parse serialized object JSON for: \(item.task.revNode.displayName)")
            applyBundledChanges(item: item, sourceNodeIds: sourceNodeIds, resume: resume, context: context)
            return
        }

        // Extract attribute order from path: "section.*.(attr1, attr2)" → ["attr1", "attr2"]
        let attrKeys: [String]
        let path = item.task.revNode.path
        if let parenStart = path.firstIndex(of: "("),
           let parenEnd = path.firstIndex(of: ")") {
            let attrString = path[path.index(after: parenStart)..<parenEnd]
            attrKeys = attrString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        } else if let firstEntry = entries.first {
            // Fallback: use first entry's keys sorted alphabetically
            attrKeys = Array(firstEntry.keys).sorted()
        } else {
            return
        }

        let attrCount = attrKeys.count
        guard attrCount > 0 else { return }

        // The LLM may add/remove entries — map by position up to sourceNodeIds capacity
        let maxEntries = sourceNodeIds.count / attrCount
        for (entryIndex, entry) in entries.prefix(maxEntries).enumerated() {
            for (attrIndex, attrKey) in attrKeys.enumerated() {
                let nodeIdIndex = entryIndex * attrCount + attrIndex
                let nodeId = sourceNodeIds[nodeIdIndex]
                guard !nodeId.isEmpty,
                      let treeNode = resume.nodes.first(where: { $0.id == nodeId }) else {
                    Logger.debug("Skipping empty/missing sourceNodeId at index \(nodeIdIndex)")
                    continue
                }

                if let arrayValue = entry[attrKey] as? [String] {
                    overwriteContainerChildren(container: treeNode, newValues: arrayValue, context: context)
                } else if let stringValue = entry[attrKey] as? String {
                    treeNode.value = stringValue
                    if treeNode.name == "name", let parent = treeNode.parent {
                        parent.name = stringValue
                    }
                }
            }
        }
        Logger.info("Applied serialized object changes (\(min(entries.count, maxEntries)) entries × \(attrCount) attrs) for: \(item.task.revNode.displayName)")
    }

    /// Overwrite a container node's children with new values, adding or removing entries as needed.
    private func overwriteContainerChildren(container: TreeNode, newValues: [String], context: ModelContext) {
        let existing = container.orderedChildren

        // Update existing children that overlap
        for (index, child) in existing.enumerated() {
            if index < newValues.count {
                child.value = newValues[index]
                child.myIndex = index
            } else {
                // Excess child — remove
                container.children?.removeAll { $0.id == child.id }
                context.delete(child)
            }
        }

        // Add new children beyond existing count
        guard newValues.count > existing.count else { return }
        for index in existing.count..<newValues.count {
            let child = TreeNode(
                name: "",
                value: newValues[index],
                children: nil,
                parent: container,
                inEditor: true,
                status: .saved,
                resume: container.resume
            )
            child.myIndex = index
            container.addChild(child)
        }
    }
}

// MARK: - Workflow Errors

enum RevisionWorkflowError: LocalizedError {
    case missingDependency(String)
    case allTasksFailed(taskCount: Int, phase: Int)

    var errorDescription: String? {
        switch self {
        case .missingDependency(let name):
            return "Missing required dependency: \(name)"
        case .allTasksFailed(let taskCount, let phase):
            return "All \(taskCount) Phase \(phase) tasks failed. Check your API key and network connection."
        }
    }
}
