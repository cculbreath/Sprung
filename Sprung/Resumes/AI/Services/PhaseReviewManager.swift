//
//  PhaseReviewManager.swift
//  Sprung
//
//  Manages the manifest-driven multi-phase review workflow.
//  Handles phase progression, LLM interaction, and change application.
//

import Foundation
import SwiftUI
import SwiftData

/// Delegate protocol for phase review manager to communicate with the view model
@MainActor
protocol PhaseReviewDelegate: AnyObject {
    var currentConversationId: UUID? { get }
    var currentModelId: String? { get }
    var openRouterService: OpenRouterService { get }

    func setConversationContext(conversationId: UUID, modelId: String)
    func showReviewSheet()
    func hideReviewSheet()
    func setProcessingRevisions(_ processing: Bool)
    func setWorkflowCompleted()
    func markWorkflowStarted()
}

/// Manages the generic manifest-driven multi-phase review workflow.
@MainActor
@Observable
class PhaseReviewManager {
    // MARK: - Dependencies
    private let llm: LLMFacade
    private let openRouterService: OpenRouterService
    private let reasoningStreamManager: ReasoningStreamManager
    private let exportCoordinator: ResumeExportCoordinator
    private let streamingService: RevisionStreamingService
    private let applicantProfileStore: ApplicantProfileStore
    private let resRefStore: ResRefStore
    weak var delegate: PhaseReviewDelegate?

    // MARK: - Phase Review State
    var phaseReviewState = PhaseReviewState()

    /// Computed property for view compatibility
    var isHierarchicalReviewActive: Bool {
        phaseReviewState.isActive
    }

    init(
        llm: LLMFacade,
        openRouterService: OpenRouterService,
        reasoningStreamManager: ReasoningStreamManager,
        exportCoordinator: ResumeExportCoordinator,
        streamingService: RevisionStreamingService,
        applicantProfileStore: ApplicantProfileStore,
        resRefStore: ResRefStore
    ) {
        self.llm = llm
        self.openRouterService = openRouterService
        self.reasoningStreamManager = reasoningStreamManager
        self.exportCoordinator = exportCoordinator
        self.streamingService = streamingService
        self.applicantProfileStore = applicantProfileStore
        self.resRefStore = resRefStore
    }

    // MARK: - Phase Detection

    /// Find sections with review phases defined that have nodes selected for AI revision.
    func sectionsWithActiveReviewPhases(for resume: Resume) -> [(section: String, phases: [TemplateManifest.ReviewPhaseConfig])] {
        Logger.debug("🔍 [sectionsWithActiveReviewPhases] Starting check...")
        Logger.debug("🔍 [sectionsWithActiveReviewPhases] template: \(resume.template != nil ? "exists" : "nil")")
        Logger.debug("🔍 [sectionsWithActiveReviewPhases] manifestData: \(resume.template?.manifestData != nil ? "\(resume.template!.manifestData!.count) bytes" : "nil")")
        Logger.debug("🔍 [sectionsWithActiveReviewPhases] rootNode: \(resume.rootNode != nil ? "exists" : "nil")")

        guard let template = resume.template,
              let rootNode = resume.rootNode else {
            Logger.warning("⚠️ [sectionsWithActiveReviewPhases] Bailing - template or rootNode nil")
            return []
        }

        guard let manifest = TemplateManifestLoader.manifest(for: template) else {
            Logger.warning("⚠️ [sectionsWithActiveReviewPhases] Failed to load manifest via TemplateManifestLoader")
            return []
        }
        Logger.debug("🔍 [sectionsWithActiveReviewPhases] manifest loaded via TemplateManifestLoader")

        Logger.debug("🔍 [sectionsWithActiveReviewPhases] reviewPhases: \(manifest.reviewPhases != nil ? "\(manifest.reviewPhases!.keys.joined(separator: ", "))" : "nil")")

        var result: [(section: String, phases: [TemplateManifest.ReviewPhaseConfig])] = []

        if let reviewPhases = manifest.reviewPhases {
            for (section, phases) in reviewPhases {
                Logger.debug("🔍 [sectionsWithActiveReviewPhases] Checking section '\(section)' with \(phases.count) phases")
                if let sectionNode = rootNode.children?.first(where: { $0.name.lowercased() == section.lowercased() }) {
                    let hasSelected = sectionNode.status == .aiToReplace || sectionNode.aiStatusChildren > 0
                    Logger.debug("🔍 [sectionsWithActiveReviewPhases] Section '\(section)' found - status=\(sectionNode.status), aiStatusChildren=\(sectionNode.aiStatusChildren), hasSelected=\(hasSelected)")
                    if hasSelected && !phases.isEmpty {
                        let sortedPhases = phases.sorted { $0.phase < $1.phase }
                        result.append((section: section, phases: sortedPhases))
                        Logger.info("📋 Section '\(section)' has \(sortedPhases.count) review phases configured - USING PHASED REVIEW")
                    }
                } else {
                    Logger.debug("🔍 [sectionsWithActiveReviewPhases] Section '\(section)' NOT found in rootNode.children")
                }
            }
        } else {
            Logger.debug("🔍 [sectionsWithActiveReviewPhases] manifest.reviewPhases is nil")
        }

        Logger.debug("🔍 [sectionsWithActiveReviewPhases] Returning \(result.count) sections with active phases")
        return result
    }

    // MARK: - Phase Workflow

    /// Start the multi-phase review workflow for a section.
    func startPhaseReview(
        resume: Resume,
        section: String,
        phases: [TemplateManifest.ReviewPhaseConfig],
        modelId: String
    ) async throws {
        delegate?.markWorkflowStarted()
        delegate?.setProcessingRevisions(true)

        // Initialize phase review state
        phaseReviewState.reset()
        phaseReviewState.isActive = true
        phaseReviewState.currentSection = section
        phaseReviewState.phases = phases
        phaseReviewState.currentPhaseIndex = 0

        guard let rootNode = resume.rootNode else {
            Logger.error("❌ No root node found for phase review")
            delegate?.setProcessingRevisions(false)
            phaseReviewState.reset()
            delegate?.setWorkflowCompleted()
            throw NSError(domain: "PhaseReviewManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No root node found"])
        }

        guard let currentPhase = phaseReviewState.currentPhase else {
            Logger.error("❌ No phases configured")
            delegate?.setProcessingRevisions(false)
            phaseReviewState.reset()
            delegate?.setWorkflowCompleted()
            return
        }

        do {
            let exportedNodes = TreeNode.exportNodesMatchingPath(currentPhase.field, from: rootNode)
            guard !exportedNodes.isEmpty else {
                Logger.warning("⚠️ No nodes found matching path '\(currentPhase.field)'")
                await advanceToNextPhase(resume: resume)
                return
            }

            Logger.info("🚀 Starting Phase \(currentPhase.phase) for '\(section)' - \(exportedNodes.count) nodes matching '\(currentPhase.field)'")

            let query = ResumeApiQuery(
                resume: resume,
                exportCoordinator: exportCoordinator,
                applicantProfile: applicantProfileStore.currentProfile(),
                allResRefs: resRefStore.resRefs,
                saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts")
            )

            let systemPrompt = query.genericSystemMessage.textContent
            let userPrompt = await query.phaseReviewPrompt(
                section: section,
                phaseNumber: currentPhase.phase,
                fieldPath: currentPhase.field,
                nodes: exportedNodes,
                isBundled: currentPhase.bundle
            )

            let model = openRouterService.findModel(id: modelId)
            let supportsReasoning = model?.supportsReasoning ?? false

            if !supportsReasoning {
                reasoningStreamManager.hideAndClear()
            }

            let reviewContainer: PhaseReviewContainer

            if supportsReasoning {
                Logger.info("🧠 Using streaming with reasoning for phase review: \(modelId)")
                let userEffort = UserDefaults.standard.string(forKey: "reasoningEffort") ?? "medium"
                let reasoning = OpenRouterReasoning(effort: userEffort, includeReasoning: true)

                let result = try await streamingService.startConversationStreaming(
                    systemPrompt: systemPrompt,
                    userMessage: userPrompt,
                    modelId: modelId,
                    reasoning: reasoning,
                    jsonSchema: ResumeApiQuery.phaseReviewSchema,
                    as: PhaseReviewContainer.self
                )

                delegate?.setConversationContext(conversationId: result.conversationId, modelId: modelId)
                reviewContainer = result.response

            } else {
                Logger.info("📝 Using non-streaming for phase review: \(modelId)")

                let (conversationId, _) = try await llm.startConversation(
                    systemPrompt: systemPrompt,
                    userMessage: userPrompt,
                    modelId: modelId
                )

                delegate?.setConversationContext(conversationId: conversationId, modelId: modelId)

                reviewContainer = try await llm.continueConversationStructured(
                    userMessage: "Please provide your review proposals in the specified JSON format.",
                    modelId: modelId,
                    conversationId: conversationId,
                    as: PhaseReviewContainer.self,
                    jsonSchema: ResumeApiQuery.phaseReviewSchema
                )
            }

            phaseReviewState.currentReview = reviewContainer
            Logger.info("✅ Phase \(currentPhase.phase) received \(reviewContainer.items.count) review proposals")

            if !currentPhase.bundle {
                phaseReviewState.pendingItemIds = reviewContainer.items.map { $0.id }
                phaseReviewState.currentItemIndex = 0
            }

            reasoningStreamManager.hideAndClear()
            delegate?.showReviewSheet()
            delegate?.setProcessingRevisions(false)

        } catch {
            Logger.error("❌ Phase review failed: \(error.localizedDescription)")
            delegate?.setProcessingRevisions(false)
            phaseReviewState.reset()
            delegate?.setWorkflowCompleted()
            throw error
        }
    }

    /// Complete the current phase and move to the next one.
    func completeCurrentPhase(resume: Resume, context: ModelContext) {
        guard let currentReview = phaseReviewState.currentReview,
              let rootNode = resume.rootNode else { return }

        TreeNode.applyPhaseReviewChanges(currentReview, to: rootNode, context: context)
        phaseReviewState.approvedReviews.append(currentReview)

        Logger.info("🔄 Phase \(phaseReviewState.currentPhaseIndex + 1) complete")

        Task {
            await advanceToNextPhase(resume: resume)
        }
    }

    /// Advance to the next phase or finish the workflow.
    private func advanceToNextPhase(resume: Resume) async {
        phaseReviewState.currentPhaseIndex += 1
        phaseReviewState.currentReview = nil
        phaseReviewState.pendingItemIds = []
        phaseReviewState.currentItemIndex = 0

        if phaseReviewState.currentPhaseIndex >= phaseReviewState.phases.count {
            finishPhaseReview(resume: resume)
            return
        }

        guard let nextPhase = phaseReviewState.currentPhase,
              let rootNode = resume.rootNode,
              let modelId = delegate?.currentModelId else {
            finishPhaseReview(resume: resume)
            return
        }

        delegate?.setProcessingRevisions(true)

        do {
            let exportedNodes = TreeNode.exportNodesMatchingPath(nextPhase.field, from: rootNode)
            guard !exportedNodes.isEmpty else {
                Logger.warning("⚠️ No nodes found for phase \(nextPhase.phase)")
                await advanceToNextPhase(resume: resume)
                return
            }

            Logger.info("🚀 Starting Phase \(nextPhase.phase) - \(exportedNodes.count) nodes")

            let query = ResumeApiQuery(
                resume: resume,
                exportCoordinator: exportCoordinator,
                applicantProfile: applicantProfileStore.currentProfile(),
                allResRefs: resRefStore.resRefs,
                saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts")
            )

            let userPrompt = await query.phaseReviewPrompt(
                section: phaseReviewState.currentSection,
                phaseNumber: nextPhase.phase,
                fieldPath: nextPhase.field,
                nodes: exportedNodes,
                isBundled: nextPhase.bundle
            )

            guard let conversationId = delegate?.currentConversationId else {
                Logger.error("❌ No conversation context for next phase")
                finishPhaseReview(resume: resume)
                return
            }

            let model = openRouterService.findModel(id: modelId)
            let supportsReasoning = model?.supportsReasoning ?? false

            let reviewContainer: PhaseReviewContainer

            if supportsReasoning {
                let userEffort = UserDefaults.standard.string(forKey: "reasoningEffort") ?? "medium"
                let reasoning = OpenRouterReasoning(effort: userEffort, includeReasoning: true)

                reviewContainer = try await streamingService.continueConversationStreaming(
                    userMessage: userPrompt,
                    modelId: modelId,
                    conversationId: conversationId,
                    reasoning: reasoning,
                    jsonSchema: ResumeApiQuery.phaseReviewSchema,
                    as: PhaseReviewContainer.self
                )
            } else {
                reviewContainer = try await llm.continueConversationStructured(
                    userMessage: userPrompt,
                    modelId: modelId,
                    conversationId: conversationId,
                    as: PhaseReviewContainer.self,
                    jsonSchema: ResumeApiQuery.phaseReviewSchema
                )
            }

            phaseReviewState.currentReview = reviewContainer

            if !nextPhase.bundle {
                phaseReviewState.pendingItemIds = reviewContainer.items.map { $0.id }
                phaseReviewState.currentItemIndex = 0
            }

            reasoningStreamManager.hideAndClear()
            delegate?.setProcessingRevisions(false)

        } catch {
            Logger.error("❌ Phase \(nextPhase.phase) failed: \(error.localizedDescription)")
            delegate?.setProcessingRevisions(false)
            await advanceToNextPhase(resume: resume)
        }
    }

    // MARK: - Item-Level Operations (Unbundled Phases)

    /// Accept current review item and move to next (for unbundled phases).
    func acceptCurrentItemAndMoveNext(resume: Resume, context: ModelContext) {
        guard var currentReview = phaseReviewState.currentReview,
              phaseReviewState.currentItemIndex < currentReview.items.count else { return }

        currentReview.items[phaseReviewState.currentItemIndex].userDecision = .accepted
        phaseReviewState.currentReview = currentReview

        phaseReviewState.currentItemIndex += 1

        if phaseReviewState.currentItemIndex >= currentReview.items.count {
            completeCurrentPhase(resume: resume, context: context)
        }
    }

    /// Reject current review item and move to next (for unbundled phases).
    func rejectCurrentItemAndMoveNext() {
        guard var currentReview = phaseReviewState.currentReview,
              phaseReviewState.currentItemIndex < currentReview.items.count else { return }

        currentReview.items[phaseReviewState.currentItemIndex].userDecision = .rejected
        phaseReviewState.currentReview = currentReview

        phaseReviewState.currentItemIndex += 1
    }

    // MARK: - Workflow Completion

    /// Finish the phase review workflow.
    func finishPhaseReview(resume: Resume) {
        Logger.info("🏁 Phase review complete for '\(phaseReviewState.currentSection)'")
        Logger.info("  - Phases completed: \(phaseReviewState.approvedReviews.count)")

        exportCoordinator.debounceExport(resume: resume)

        phaseReviewState.reset()
        delegate?.hideReviewSheet()
        delegate?.setWorkflowCompleted()
    }

    /// Check if there are unapplied approved changes.
    func hasUnappliedApprovedChanges() -> Bool {
        !phaseReviewState.approvedReviews.isEmpty || phaseReviewState.currentReview != nil
    }

    /// Apply all approved changes and close.
    func applyApprovedChangesAndClose(resume: Resume, context: ModelContext) {
        guard let rootNode = resume.rootNode else { return }

        if let currentReview = phaseReviewState.currentReview {
            TreeNode.applyPhaseReviewChanges(currentReview, to: rootNode, context: context)
        }

        for review in phaseReviewState.approvedReviews {
            TreeNode.applyPhaseReviewChanges(review, to: rootNode, context: context)
        }

        exportCoordinator.debounceExport(resume: resume)

        phaseReviewState.reset()
        delegate?.hideReviewSheet()
        delegate?.setWorkflowCompleted()
    }

    /// Discard all changes and close.
    func discardAllAndClose() {
        phaseReviewState.reset()
        delegate?.hideReviewSheet()
        delegate?.setWorkflowCompleted()
    }
}
