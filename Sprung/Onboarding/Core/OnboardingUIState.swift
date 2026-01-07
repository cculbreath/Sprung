import Foundation
import Observation
import SwiftyJSON
/// Observable state container for the Onboarding UI.
/// This class holds all state required by SwiftUI views, updated via events from the Coordinator.
@MainActor
@Observable
final class OnboardingUIState {
    // MARK: - Processing State
    var isProcessing: Bool = false
    var currentStatusMessage: String?
    var isActive: Bool = false

    // MARK: - Batch Upload State
    /// True when a batch of documents is being processed (extraction in progress)
    /// Used to prevent validation prompts from interrupting batch uploads
    var hasBatchUploadInProgress: Bool = false

    // MARK: - Extraction State (Non-Blocking)
    /// True when document extraction is in progress (PDF processing, git analysis)
    /// Unlike isProcessing, this does NOT block chat input - allows dossier questions during "dead time"
    var isExtractionInProgress: Bool = false
    /// Status message to display during extraction (e.g., "Extracting resume.pdf...")
    var extractionStatusMessage: String?
    // MARK: - Chat State
    var messages: [OnboardingMessage] = []
    var modelAvailabilityMessage: String?
    /// Stores the original text from a failed message send, to be restored to the input box
    var failedMessageText: String?
    /// Error message to display when a message send fails
    var failedMessageError: String?
    // MARK: - Timeline State
    var skeletonTimeline: JSON?
    /// UI-only counter for SwiftUI change detection when timeline updates occur
    var timelineUIChangeToken: Int = 0
    /// True when LLM has activated the timeline editor (via display_timeline_entries_for_review)
    var isTimelineEditorActive: Bool = false
    /// ID of the currently expanded/editing timeline entry (nil = all collapsed)
    var editingTimelineEntryId: String?
    // MARK: - Wizard State
    var wizardStep: StateCoordinator.WizardStep = .voice
    var completedWizardSteps: Set<StateCoordinator.WizardStep> = []
    var phase: InterviewPhase = .phase1VoiceContext
    // MARK: - Tool Pane State (Mirrored from ToolHandler)
    // Note: ToolHandler (via ToolRouter) manages its own state, but we might want to mirror it here
    // or keep accessing it via the router. For now, we'll keep the pattern of accessing via router
    // to avoid duplication, but we can add computed properties if needed.
    // MARK: - Sync Caches (Mirrored from StateCoordinator)
    var pendingExtraction: OnboardingPendingExtraction?
    var pendingStreamingStatus: String?
    var evidenceRequirements: [EvidenceRequirement] = []
    /// Stores last shown profile summary to display until skeleton timeline loads
    var lastApplicantProfileSummary: JSON?

    // MARK: - Document Collection Phase
    /// True when document collection UI should be displayed (Phase 2)
    /// Set by open_document_collection tool, cleared when user clicks "Assess Completeness"
    var isDocumentCollectionActive: Bool = false

    // MARK: - Multi-Agent Workflow State
    /// True when card assignments have been proposed and await user approval
    /// Set by .mergeComplete event, cleared when generation begins
    var cardAssignmentsReadyForApproval: Bool = false
    /// Number of card assignments proposed
    var proposedAssignmentCount: Int = 0
    /// Number of documentation gaps identified
    var identifiedGapCount: Int = 0
    /// True when card inventories are being merged (after Done with Uploads)
    var isMergingCards: Bool = false
    /// True when actively generating knowledge cards
    var isGeneratingCards: Bool = false

    // MARK: - Objective Status (for Phase 3 subphase tracking)
    var objectiveStatuses: [String: String] = [:]

    // MARK: - Guidance Flags
    /// True when custom.jobTitles was enabled during section configuration
    var shouldGenerateTitleSets: Bool = false

    // MARK: - Interview Completion State
    /// Set to true when interview transitions to .complete phase
    /// View observes this to close the window automatically
    var interviewJustCompleted: Bool = false

    // MARK: - Preferences
    var preferences: OnboardingPreferences
    init(preferences: OnboardingPreferences) {
        self.preferences = preferences
    }
    // MARK: - Update Methods
    func updateProcessing(isProcessing: Bool, statusMessage: String?) {
        self.isProcessing = isProcessing
        if let statusMessage = statusMessage {
            self.currentStatusMessage = statusMessage
        } else if !isProcessing {
            self.currentStatusMessage = nil
        }
    }
    func updateTimeline(_ timeline: JSON?) {
        let oldToken = self.timelineUIChangeToken
        self.skeletonTimeline = timeline
        self.timelineUIChangeToken += 1
        let cardCount = timeline?["experiences"].array?.count ?? 0
        Logger.info("📊 OnboardingUIState.updateTimeline: token \(oldToken) → \(self.timelineUIChangeToken), cards=\(cardCount)", category: .ai)
    }
    func updateWizardProgress(step: StateCoordinator.WizardStep, completed: Set<StateCoordinator.WizardStep>) {
        self.wizardStep = step
        self.completedWizardSteps = completed
    }

    /// Update extraction state (non-blocking - chat remains enabled)
    func updateExtraction(inProgress: Bool, statusMessage: String? = nil) {
        self.isExtractionInProgress = inProgress
        self.extractionStatusMessage = statusMessage
        if !inProgress {
            self.extractionStatusMessage = nil
        }
    }

    /// Handle a failed message send by removing it from transcript and storing for input restoration
    func handleMessageFailure(messageId: String, originalText: String, error: String) {
        // Remove the failed message from the transcript
        if let uuid = UUID(uuidString: messageId) {
            messages.removeAll { $0.id == uuid }
        }
        // Store the original text and error for UI to restore
        failedMessageText = originalText
        failedMessageError = error
        Logger.info("💬 Message failure handled: removed from transcript, text ready for restoration", category: .ai)
    }

    /// Clear the failed message state after the UI has restored the text
    func clearFailedMessage() {
        failedMessageText = nil
        failedMessageError = nil
    }
}
