//
//  RevisionWorkflowState.swift
//  Sprung
//
//  Manages workflow state and coordination flags for the resume revision process.
//

import Foundation

/// State object managing revision workflow coordination and progress tracking.
@Observable
class RevisionWorkflowState {
    /// The type of workflow currently active.
    enum WorkflowKind {
        case customize
        case clarifying
    }

    // MARK: - Workflow State

    /// The currently active workflow type, if any.
    private(set) var activeWorkflow: WorkflowKind?

    /// Whether a workflow is currently in progress.
    var workflowInProgress: Bool = false

    /// Whether the AI is currently processing a resubmission.
    var aiResubmit: Bool = false

    // MARK: - Processing State

    /// Whether the system is currently processing revisions from the LLM.
    private(set) var isProcessingRevisions: Bool = false

    // MARK: - Conversation Context

    /// The current conversation ID for multi-turn interactions.
    private(set) var currentConversationId: UUID?

    /// The current model ID being used for LLM interactions.
    var currentModelId: String?

    // MARK: - Workflow Control

    /// Check if a specific workflow is currently busy.
    func isWorkflowBusy(_ kind: WorkflowKind) -> Bool {
        guard activeWorkflow == kind else { return false }
        return workflowInProgress || aiResubmit
    }

    /// Mark a workflow as started.
    func markWorkflowStarted(_ kind: WorkflowKind) {
        activeWorkflow = kind
        workflowInProgress = true
    }

    /// Mark the current workflow as completed.
    func markWorkflowCompleted(reset: Bool) {
        workflowInProgress = false
        if reset {
            activeWorkflow = nil
        }
    }

    /// Set the conversation context for multi-turn interactions.
    func setConversationContext(conversationId: UUID, modelId: String) {
        self.currentConversationId = conversationId
        self.currentModelId = modelId
    }

    /// Set whether the system is processing revisions.
    func setProcessingRevisions(_ processing: Bool) {
        isProcessingRevisions = processing
    }
}
