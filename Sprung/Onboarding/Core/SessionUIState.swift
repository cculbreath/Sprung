import Foundation
import SwiftyJSON

/// Domain service for UI state and tool gating logic.
/// Owns all waiting states, pending prompts, and publishes tool permissions.
/// KEY INNOVATION: The service that owns waiting state also publishes tool permissions.
actor SessionUIState: OnboardingEventEmitter {
    // MARK: - Event System

    let eventBus: EventCoordinator

    // MARK: - Policy

    private let phasePolicy: PhasePolicy
    private var currentPhase: InterviewPhase

    // MARK: - Session State

    private(set) var isActive = false
    private(set) var isProcessing = false

    // MARK: - Waiting States

    enum WaitingState: String {
        case selection
        case upload
        case validation
        case extraction
        case processing
    }

    private(set) var waitingState: WaitingState?

    // MARK: - Pending UI Prompts

    private(set) var pendingUploadRequest: OnboardingUploadRequest?
    private(set) var pendingChoicePrompt: OnboardingChoicePrompt?
    private(set) var pendingValidationPrompt: OnboardingValidationPrompt?
    private(set) var pendingExtraction: OnboardingPendingExtraction?
    private(set) var pendingStreamingStatus: String?
    private(set) var pendingPhaseAdvanceRequest: OnboardingPhaseAdvanceRequest?

    // MARK: - Synchronous Caches (for SwiftUI)

    nonisolated(unsafe) private(set) var isProcessingSync = false
    nonisolated(unsafe) private(set) var isActiveSync = false
    nonisolated(unsafe) private(set) var pendingExtractionSync: OnboardingPendingExtraction?
    nonisolated(unsafe) private(set) var pendingStreamingStatusSync: String?
    nonisolated(unsafe) private(set) var pendingPhaseAdvanceRequestSync: OnboardingPhaseAdvanceRequest?

    // MARK: - Initialization

    init(eventBus: EventCoordinator, phasePolicy: PhasePolicy, initialPhase: InterviewPhase) {
        self.eventBus = eventBus
        self.phasePolicy = phasePolicy
        self.currentPhase = initialPhase
        Logger.info("🎨 SessionUIState initialized", category: .ai)
    }

    // MARK: - Phase Updates

    /// Update current phase (for tool permission calculation)
    func setPhase(_ phase: InterviewPhase) async {
        currentPhase = phase
        // Re-publish tool permissions when phase changes
        await publishToolPermissions()
    }

    // MARK: - Session State

    /// Set processing state
    func setProcessingState(_ processing: Bool) async {
        isProcessing = processing
        isProcessingSync = processing

        // Emit event for other coordinators
        await emit(.processingStateChanged(processing))
    }

    /// Set active state
    func setActiveState(_ active: Bool) {
        isActive = active
        isActiveSync = active
    }

    // MARK: - Waiting State Management

    /// Set waiting state and publish tool permissions
    /// KEY: This service owns waiting state AND publishes tool permissions
    func setWaitingState(_ state: WaitingState?) async {
        let previousState = waitingState
        waitingState = state

        // Publish tool permissions based on new waiting state
        await publishToolPermissions()

        // Emit waiting state change event
        await emit(.waitingStateChanged(state?.rawValue))

        // Log state transition
        if let state = state {
            Logger.info("⏸️  ENTERING WAITING STATE: \(state.rawValue)", category: .ai)
        } else if let previousState = previousState {
            Logger.info("▶️  EXITING WAITING STATE (was: \(previousState.rawValue))", category: .ai)
        }
    }

    /// Clear waiting state and restore normal tools
    func clearWaitingState() async {
        await setWaitingState(nil)
    }

    /// Get current waiting state
    func getWaitingState() -> WaitingState? {
        waitingState
    }

    // MARK: - Pending Prompts

    /// Set pending upload request
    func setPendingUpload(_ request: OnboardingUploadRequest?) async {
        pendingUploadRequest = request
        let newWaitingState: WaitingState? = request != nil ? .upload : nil
        await setWaitingState(newWaitingState)
    }

    /// Set pending choice prompt
    func setPendingChoice(_ prompt: OnboardingChoicePrompt?) async {
        pendingChoicePrompt = prompt
        let newWaitingState: WaitingState? = prompt != nil ? .selection : nil
        await setWaitingState(newWaitingState)
    }

    /// Set pending validation prompt
    func setPendingValidation(_ prompt: OnboardingValidationPrompt?) async {
        pendingValidationPrompt = prompt
        let newWaitingState: WaitingState? = prompt != nil ? .validation : nil
        await setWaitingState(newWaitingState)
    }

    /// Set pending extraction
    func setPendingExtraction(_ extraction: OnboardingPendingExtraction?) async {
        pendingExtraction = extraction
        pendingExtractionSync = extraction
        let newWaitingState: WaitingState? = extraction != nil ? .extraction : nil
        await setWaitingState(newWaitingState)

        // Emit event
        await emit(.pendingExtractionUpdated(extraction))
    }

    /// Set streaming status
    func setStreamingStatus(_ status: String?) {
        pendingStreamingStatus = status
        pendingStreamingStatusSync = status
    }

    /// Set pending phase advance request
    func setPendingPhaseAdvanceRequest(_ request: OnboardingPhaseAdvanceRequest?) {
        pendingPhaseAdvanceRequest = request
        pendingPhaseAdvanceRequestSync = request
    }

    // MARK: - Tool Gating Logic

    // Tool Gating Strategy:
    // When the system enters a waiting state (upload, selection, validation, extraction, processing),
    // ALL tools are gated (empty tool set) to prevent the LLM from calling tools while waiting for
    // user input. This ensures:
    // 1. The LLM cannot make progress until the user responds
    // 2. Tool calls don't interfere with the UI continuation flow
    // 3. Clear state boundaries between AI processing and user interaction
    //
    // The gating is enforced at two levels:
    // 1. LLMMessenger: Filters tool schemas based on allowedTools from .stateAllowedToolsUpdated events
    // 2. ToolExecutionCoordinator: Validates waiting state before executing any tool call
    //
    // When the waiting state is cleared, normal phase-based tool permissions are restored.

    /// Publish tool permissions based on current waiting state and phase
    /// KEY METHOD: This is where SessionUIState publishes tool permissions
    private func publishToolPermissions() async {
        let tools: Set<String>

        if let waitingState = waitingState {
            // During waiting states, restrict to empty set (only continuation path allowed)
            tools = []
            await emit(.stateAllowedToolsUpdated(tools: tools))

            Logger.info("🚫 ALL TOOLS GATED - Waiting for user input (state: \(waitingState.rawValue))", category: .ai)
            let normalTools = getAllowedToolsForCurrentPhase()
            if !normalTools.isEmpty {
                Logger.info("   ⛔️ Blocked tools (\(normalTools.count)): \(normalTools.sorted().joined(separator: ", "))", category: .ai)
            }
        } else {
            // No waiting state - use normal phase-based tools
            tools = getAllowedToolsForCurrentPhase()
            await emit(.stateAllowedToolsUpdated(tools: tools))

            if tools.isEmpty {
                Logger.info("🔧 No tools available in current phase", category: .ai)
            } else {
                Logger.info("🔧 Tools enabled (\(tools.count)): \(tools.sorted().joined(separator: ", "))", category: .ai)
            }
        }
    }

    /// Get allowed tools for the current phase
    private func getAllowedToolsForCurrentPhase() -> Set<String> {
        return phasePolicy.allowedTools[currentPhase] ?? []
    }

    /// Public API to trigger tool permission republication
    func publishToolPermissionsNow() async {
        await publishToolPermissions()
    }

    // MARK: - State Management

    /// Reset all UI state
    func reset() {
        isActive = false
        isProcessing = false
        waitingState = nil
        pendingUploadRequest = nil
        pendingChoicePrompt = nil
        pendingValidationPrompt = nil
        pendingExtraction = nil
        pendingStreamingStatus = nil
        pendingPhaseAdvanceRequest = nil

        // Reset sync caches
        isProcessingSync = false
        isActiveSync = false
        pendingExtractionSync = nil
        pendingStreamingStatusSync = nil
        pendingPhaseAdvanceRequestSync = nil

        Logger.info("🔄 SessionUIState reset", category: .ai)
    }
}
