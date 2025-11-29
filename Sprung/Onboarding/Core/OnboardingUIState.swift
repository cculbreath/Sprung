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
    var drafts: [KnowledgeCardDraft] = []
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
        self.skeletonTimeline = timeline
        self.timelineUIChangeToken += 1
    }
    func updateWizardProgress(step: StateCoordinator.WizardStep, completed: Set<StateCoordinator.WizardStep>) {
        self.wizardStep = step
        self.completedWizardSteps = completed
    }
}
