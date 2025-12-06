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
    // MARK: - Wizard State
    var wizardStep: StateCoordinator.WizardStep = .introduction
    var completedWizardSteps: Set<StateCoordinator.WizardStep> = []
    var phase: InterviewPhase = .phase1CoreFacts
    // MARK: - Tool Pane State (Mirrored from ToolHandler)
    // Note: ToolHandler (via ToolRouter) manages its own state, but we might want to mirror it here
    // or keep accessing it via the router. For now, we'll keep the pattern of accessing via router
    // to avoid duplication, but we can add computed properties if needed.
    // MARK: - Sync Caches (Mirrored from StateCoordinator)
    var pendingExtraction: OnboardingPendingExtraction?
    var pendingStreamingStatus: String?
    var artifactRecords: [JSON] = []
    var pendingPhaseAdvanceRequest: OnboardingPhaseAdvanceRequest?
    var evidenceRequirements: [EvidenceRequirement] = []
    /// Stores last shown profile summary to display until skeleton timeline loads
    var lastApplicantProfileSummary: JSON?
    // MARK: - Knowledge Card Plan State
    var knowledgeCardPlan: [KnowledgeCardPlanItem] = []
    var knowledgeCardPlanFocus: String?
    var knowledgeCardPlanMessage: String?

    // MARK: - Objective Status (for Phase 3 subphase tracking)
    var objectiveStatuses: [String: String] = [:]

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
