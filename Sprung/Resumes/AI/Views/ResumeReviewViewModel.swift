// Sprung/Resumes/AI/Views/ResumeReviewViewModel.swift
import Foundation
import SwiftUI

/// Pre-mutation snapshot of the 'Skills and Expertise' subtree.
/// Captures node values, ordering, and child membership so AI mutations
/// (rewrites, merges, reorders) can be rejected and fully restored.
@MainActor
private struct SkillsTreeSnapshot {
    private struct NodeState {
        let node: TreeNode
        let name: String
        let value: String
        let myIndex: Int
        /// Ordered child references at snapshot time (nil when node had no children array).
        let orderedChildren: [TreeNode]?
    }
    private var states: [NodeState] = []

    init?(resume: Resume) {
        guard let section = FixOverflowService.skillsSection(in: resume) else { return nil }
        capture(section)
    }

    private mutating func capture(_ node: TreeNode) {
        states.append(NodeState(
            node: node,
            name: node.name,
            value: node.value,
            myIndex: node.myIndex,
            orderedChildren: node.children.map { children in
                children.sorted { $0.myIndex < $1.myIndex }
            }
        ))
        for child in node.children ?? [] {
            capture(child)
        }
    }

    /// Whether the live tree currently differs from the snapshot.
    var hasChanges: Bool {
        states.contains { state in
            if state.node.name != state.name || state.node.value != state.value || state.node.myIndex != state.myIndex {
                return true
            }
            guard let expected = state.orderedChildren else { return false }
            let current = (state.node.children ?? []).sorted { $0.myIndex < $1.myIndex }
            return current.map(\.id) != expected.map(\.id)
        }
    }

    /// Restore every captured node to its snapshot state, re-attaching any
    /// nodes that were detached by merge operations.
    func restore() {
        for state in states {
            state.node.name = state.name
            state.node.value = state.value
            state.node.myIndex = state.myIndex
        }
        for state in states {
            guard let expected = state.orderedChildren else { continue }
            let current = (state.node.children ?? []).sorted { $0.myIndex < $1.myIndex }
            if current.map(\.id) != expected.map(\.id) {
                state.node.children = expected
            }
        }
    }

    /// Captured nodes that are no longer reachable from the snapshot root —
    /// detached by merge operations. On accept these must be deleted from the
    /// model context or they persist as unreachable subtrees forever (reject
    /// re-attaches them via `restore()`).
    func detachedNodes() -> [TreeNode] {
        guard let root = states.first?.node else { return [] }
        var reachable = Set<ObjectIdentifier>()
        func walk(_ node: TreeNode) {
            reachable.insert(ObjectIdentifier(node))
            for child in node.children ?? [] {
                walk(child)
            }
        }
        walk(root)
        return states.map(\.node).filter { !reachable.contains(ObjectIdentifier($0)) }
    }
}

/// A completed AI skills mutation awaiting the user's accept/reject decision.
struct PendingSkillsChangeReview {
    let operationTitle: String
    let diffSummary: String
}

@MainActor
@Observable
class ResumeReviewViewModel {
    // MARK: - State Properties
    // General review state
    private(set) var reviewResponseText: String = ""
    private(set) var isProcessingGeneral: Bool = false
    private(set) var generalError: String?
    // Fix Overflow state
    private(set) var fixOverflowStatusMessage: String = ""
    private(set) var fixOverflowChangeMessage: String = ""
    private(set) var isProcessingFixOverflow: Bool = false
    private(set) var fixOverflowError: String?
    private(set) var currentPageCount: Int = 0
    private(set) var currentPageLimit: Int = 0
    // Accept/reject gate for AI skills mutations
    private(set) var pendingChangeReview: PendingSkillsChangeReview?
    private var skillsSnapshot: SkillsTreeSnapshot?
    private var reviewedResume: Resume?
    /// Set when the hosting sheet disappears. A run that completes after this
    /// auto-rejects (restores the snapshot) instead of presenting a review
    /// gate into a dead view.
    private var isSheetDismissed = false
    // MARK: - Dependencies
    private var reasoningStreamManager: ReasoningStreamManager?
    private var openRouterService: OpenRouterService?
    private var exportCoordinator: ResumeExportCoordinator?
    private var coverRefStore: CoverRefStore?
    private var reviewService: ResumeReviewService?
    private var fixOverflowService: FixOverflowService?
    private var reorderSkillsService: ReorderSkillsService?
    // MARK: - Initialization
    func initialize(
        llmFacade: LLMFacade,
        exportCoordinator: ResumeExportCoordinator,
        reasoningStreamManager: ReasoningStreamManager,
        openRouterService: OpenRouterService,
        coverRefStore: CoverRefStore
    ) {
        self.reasoningStreamManager = reasoningStreamManager
        self.openRouterService = openRouterService
        self.exportCoordinator = exportCoordinator
        self.coverRefStore = coverRefStore
        reviewService = ResumeReviewService(llmFacade: llmFacade)
        fixOverflowService = FixOverflowService(llm: llmFacade, exportCoordinator: exportCoordinator)
        reorderSkillsService = ReorderSkillsService(llm: llmFacade, exportCoordinator: exportCoordinator)
        isSheetDismissed = false
        resetChangeMessage()
    }

    /// Called from the sheet's `onDisappear`. While a review is pending the
    /// sheet blocks dismissal, but force-dismissals (window teardown) can still
    /// land here — reject immediately so the mutations never stick silently.
    /// Runs that finish after dismissal auto-reject in `presentReviewIfNeeded`.
    func handleSheetDismissed() {
        isSheetDismissed = true
        if pendingChangeReview != nil {
            Task { await rejectPendingChanges() }
        }
    }
    // MARK: - Public Methods
    func handleSubmit(
        reviewType: ResumeReviewType,
        resume: Resume,
        selectedModel: String,
        customOptions: CustomReviewOptions?,
        allowEntityMerge: Bool
    ) {
        resetState()
        // No model configured → surface the configuration error; never substitute a default.
        guard !selectedModel.trimmingCharacters(in: .whitespaces).isEmpty else {
            let error = ModelConfigurationError.modelNotConfigured(
                settingKey: "resumeReviewSelectedModel",
                operationName: "Resume Review"
            )
            generalError = [error.localizedDescription, error.recoverySuggestion]
                .compactMap { $0 }
                .joined(separator: " ")
            return
        }
        switch reviewType {
        case .fixOverflow:
            Task {
                await performFixOverflow(resume: resume, allowEntityMerge: allowEntityMerge, selectedModel: selectedModel)
            }
        case .reorderSkills:
            Task {
                await performReorderSkills(resume: resume, selectedModel: selectedModel)
            }
        default:
            performGeneralReview(
                reviewType: reviewType,
                resume: resume,
                selectedModel: selectedModel,
                customOptions: customOptions
            )
        }
    }
    func cancelRequest() {
        reviewService?.cancelRequest()
        isProcessingGeneral = false
        isProcessingFixOverflow = false
        fixOverflowStatusMessage = "Operation stopped by user."
    }
    func resetOnReviewTypeChange() {
        reviewResponseText = ""
        fixOverflowStatusMessage = ""
        isProcessingGeneral = false
        isProcessingFixOverflow = false
        generalError = nil
        fixOverflowError = nil
    }
    func resetChangeMessage() {
        fixOverflowChangeMessage = ""
    }
    // MARK: - Accept/Reject
    /// Keep the AI mutations: delete the nodes merge operations detached
    /// (otherwise they persist unreachably in SwiftData forever), then discard
    /// the snapshot.
    func acceptPendingChanges() {
        if let snapshot = skillsSnapshot {
            for node in snapshot.detachedNodes() {
                // children carry a cascade delete rule, so the whole detached
                // subtree goes with the node.
                node.modelContext?.delete(node)
            }
        }
        pendingChangeReview = nil
        skillsSnapshot = nil
        reviewedResume = nil
        fixOverflowStatusMessage = "Changes accepted."
    }
    /// Discard the AI mutations: restore the snapshot and re-render.
    func rejectPendingChanges() async {
        guard let snapshot = skillsSnapshot, let resume = reviewedResume else {
            pendingChangeReview = nil
            return
        }
        snapshot.restore()
        pendingChangeReview = nil
        skillsSnapshot = nil
        reviewedResume = nil
        fixOverflowChangeMessage = ""
        do {
            try await exportCoordinator?.forceRender(for: resume)
            fixOverflowStatusMessage = "Changes rejected — original content restored."
        } catch {
            fixOverflowStatusMessage = "Changes rejected — original content restored, but re-rendering failed: \(error.localizedDescription)"
        }
    }
    // MARK: - Private Methods
    private func resetState() {
        reviewResponseText = ""
        fixOverflowStatusMessage = ""
        fixOverflowChangeMessage = ""
        generalError = nil
        fixOverflowError = nil
        pendingChangeReview = nil
        skillsSnapshot = nil
        reviewedResume = nil
        currentPageCount = 0
        currentPageLimit = 0
    }
    /// Present the accept/reject gate when the operation actually mutated the tree.
    /// If the sheet was dismissed while the run was still processing, nobody is
    /// left to review — restore the snapshot (auto-reject) instead of presenting
    /// a gate into a dead view.
    private func presentReviewIfNeeded(resume: Resume, operationTitle: String, diffSummary: String) async {
        guard let snapshot = skillsSnapshot, snapshot.hasChanges else {
            skillsSnapshot = nil
            reviewedResume = nil
            return
        }
        if isSheetDismissed {
            snapshot.restore()
            skillsSnapshot = nil
            reviewedResume = nil
            fixOverflowChangeMessage = ""
            Logger.warning("\(operationTitle): review sheet dismissed before the run completed — AI changes auto-rejected")
            do {
                try await exportCoordinator?.forceRender(for: resume)
            } catch {
                Logger.error("\(operationTitle): re-render after auto-reject failed: \(error.localizedDescription)")
            }
            return
        }
        reviewedResume = resume
        pendingChangeReview = PendingSkillsChangeReview(
            operationTitle: operationTitle,
            diffSummary: diffSummary
        )
    }
    private func performGeneralReview(
        reviewType: ResumeReviewType,
        resume: Resume,
        selectedModel: String,
        customOptions: CustomReviewOptions?
    ) {
        isProcessingGeneral = true
        reviewResponseText = "Submitting request..."
        reviewService?.sendReviewRequest(
            reviewType: reviewType,
            resume: resume,
            modelId: selectedModel,
            customOptions: reviewType == .custom ? customOptions : nil,
            onProgress: { [weak self] contentChunk in
                Task { @MainActor in
                    guard let self = self else { return }
                    if self.reviewResponseText == "Submitting request..." {
                        self.reviewResponseText = ""
                    }
                    self.reviewResponseText += contentChunk
                }
            },
            onComplete: { [weak self] result in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.isProcessingGeneral = false
                    switch result {
                    case let .success(finalMessage):
                        if self.reviewResponseText == "Submitting request..." || self.reviewResponseText.isEmpty {
                            self.reviewResponseText = finalMessage
                        }
                        if self.reviewResponseText.isEmpty {
                            self.reviewResponseText = "Review complete. No specific feedback provided."
                        }
                    case let .failure(error):
                        self.handleGeneralError(error)
                        if self.reviewResponseText == "Submitting request..." || !self.reviewResponseText.isEmpty {
                            self.reviewResponseText = ""
                        }
                    }
                }
            }
        )
    }
    private func handleGeneralError(_ error: Error) {
        if let nsError = error as NSError? {
            if nsError.domain == "OpenAIAPI" {
                generalError = "API Error: \(nsError.localizedDescription)"
            } else if let errorInfo = nsError.userInfo[NSLocalizedDescriptionKey] as? String {
                generalError = "Error: \(errorInfo)\nPlease try again or select a different model in Settings."
            } else {
                generalError = "Error: \(error.localizedDescription)"
            }
        } else {
            generalError = "Error: \(error.localizedDescription)"
        }
    }
    private func performFixOverflow(resume: Resume, allowEntityMerge: Bool, selectedModel: String) async {
        isProcessingFixOverflow = true
        fixOverflowStatusMessage = "Starting skills optimization..."
        guard let openRouterService = openRouterService, let reasoningStreamManager = reasoningStreamManager else {
            fixOverflowError = "Service dependencies not initialized"
            isProcessingFixOverflow = false
            return
        }
        // Check if model supports reasoning and prepare callback
        let model = openRouterService.findModel(id: selectedModel)
        let supportsReasoning = model?.supportsReasoning ?? false
        let reasoningCallback: ((String) -> Void)? = supportsReasoning ? { reasoningContent in
            Task { @MainActor in
                reasoningStreamManager.reasoningText += reasoningContent
            }
        } : nil
        if supportsReasoning {
            reasoningStreamManager.startReasoning(modelName: selectedModel)
        }
        // Snapshot the skills subtree so the user can reject the mutations.
        skillsSnapshot = SkillsTreeSnapshot(resume: resume)
        let result = await fixOverflowService?.performFixOverflow(
            resume: resume,
            allowEntityMerge: allowEntityMerge,
            selectedModel: selectedModel,
            maxIterations: UserDefaults.standard.integer(forKey: "fixOverflowMaxIterations") == 0 ? 3 : UserDefaults.standard.integer(forKey: "fixOverflowMaxIterations"),
            writersVoice: coverRefStore?.writersVoice ?? "",
            supportsReasoning: supportsReasoning,
            onStatusUpdate: { [weak self] status in
                Task { @MainActor in
                    self?.fixOverflowStatusMessage = status.statusMessage
                    self?.fixOverflowChangeMessage = status.changeMessage
                    self?.currentPageCount = status.pageCount
                    self?.currentPageLimit = status.pageLimit
                }
            },
            onReasoningUpdate: reasoningCallback
        )
        switch result {
        case .success(let finalStatus):
            fixOverflowStatusMessage = finalStatus
        case .failure(let error):
            fixOverflowError = error.localizedDescription
        case .none:
            fixOverflowError = "Fix Overflow service unavailable."
        }
        // Even on failure, applied iterations must be reviewable — never silent.
        await presentReviewIfNeeded(
            resume: resume,
            operationTitle: "Fix Overflow",
            diffSummary: fixOverflowChangeMessage
        )
        // Complete reasoning stream
        if supportsReasoning {
            reasoningStreamManager.stopStream()
        }
        isProcessingFixOverflow = false
    }
    private func performReorderSkills(resume: Resume, selectedModel: String) async {
        isProcessingFixOverflow = true
        fixOverflowStatusMessage = "Starting skills reordering..."
        // Snapshot the skills subtree so the user can reject the reordering.
        skillsSnapshot = SkillsTreeSnapshot(resume: resume)
        let result = await reorderSkillsService?.performReorderSkills(
            resume: resume,
            selectedModel: selectedModel
        ) { [weak self] status in
            Task { @MainActor in
                self?.fixOverflowStatusMessage = status.statusMessage
                self?.fixOverflowChangeMessage = status.changeMessage
            }
        }
        switch result {
        case .success(let finalStatus):
            fixOverflowStatusMessage = finalStatus
        case .failure(let error):
            fixOverflowError = error.localizedDescription
        case .none:
            fixOverflowError = "Reorder Skills service unavailable."
        }
        await presentReviewIfNeeded(
            resume: resume,
            operationTitle: "Reorder Skills",
            diffSummary: fixOverflowChangeMessage
        )
        isProcessingFixOverflow = false
    }
}
