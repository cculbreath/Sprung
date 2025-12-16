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
    private var excludedTools: Set<String> = []
    /// Cache of last published tools to avoid duplicate emissions
    private var lastPublishedTools: Set<String>?
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

    // MARK: - KC Validation Queue (Auto-Validation from Agent Completion)
    /// Queue of card IDs waiting for user validation (FIFO order)
    /// Cards are enqueued automatically when KC agents complete
    private(set) var pendingKCValidationQueue: [String] = []
    /// Whether current validation is from KC auto-queue (vs tool-initiated)
    private(set) var isAutoValidation: Bool = false
    // MARK: - Synchronous Caches (for SwiftUI)
    nonisolated(unsafe) private(set) var isProcessingSync = false
    nonisolated(unsafe) private(set) var isActiveSync = false
    nonisolated(unsafe) private(set) var pendingExtractionSync: OnboardingPendingExtraction?
    nonisolated(unsafe) private(set) var pendingStreamingStatusSync: String?
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
    func setProcessingState(_ processing: Bool, emitEvent: Bool = true) async {
        let didChange = isProcessing != processing
        isProcessing = processing
        isProcessingSync = processing
        guard emitEvent, didChange else { return }
        // Emit event for other coordinators only when the value changes
        await emit(.processingStateChanged(processing))
    }
    /// Set active state
    func setActiveState(_ active: Bool) async {
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
        // Only set waiting state for validation mode, not editor mode
        // Editor mode allows tools to continue (e.g., timeline card creation)
        let newWaitingState: WaitingState? = (prompt != nil && prompt?.mode == .validation) ? .validation : nil
        await setWaitingState(newWaitingState)
    }

    // MARK: - KC Auto-Validation Queue Management

    /// Enqueue a card ID for auto-validation
    /// If no validation is currently active, immediately emit validation request
    /// Returns: whether the card was queued (true) or immediately presented (false)
    func enqueueKCValidation(_ cardId: String) {
        pendingKCValidationQueue.append(cardId)
        Logger.info("📋 KC validation queued: \(cardId) (queue size: \(pendingKCValidationQueue.count))", category: .ai)
    }

    /// Get the next card ID from the validation queue without removing it
    func peekNextKCValidation() -> String? {
        pendingKCValidationQueue.first
    }

    /// Remove and return the next card ID from the validation queue
    func dequeueNextKCValidation() -> String? {
        guard !pendingKCValidationQueue.isEmpty else { return nil }
        return pendingKCValidationQueue.removeFirst()
    }

    /// Check if there are pending KC validations in the queue
    func hasQueuedKCValidations() -> Bool {
        !pendingKCValidationQueue.isEmpty
    }

    /// Set whether current validation is auto-initiated (from KC agent completion)
    func setAutoValidation(_ isAuto: Bool) {
        isAutoValidation = isAuto
    }

    /// Clear the KC validation queue
    func clearKCValidationQueue() {
        pendingKCValidationQueue.removeAll()
        isAutoValidation = false
        Logger.info("🗑️ KC validation queue cleared", category: .ai)
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
    // MARK: - Tool Gating Logic
    // Tool Gating Strategy:
    // When the system enters a waiting state (upload, selection, validation, processing),
    // ALL tools are gated (empty tool set) to prevent the LLM from calling tools while waiting for
    // user input. This ensures:
    // 1. The LLM cannot make progress until the user responds
    // 2. Tool calls don't interfere with the UI continuation flow
    // 3. Clear state boundaries between AI processing and user interaction
    //
    // EXCEPTION: During extraction (.extraction state), tools remain ENABLED to allow
    // dossier question collection during the "dead time" of PDF extraction (2+ minutes).
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
        if let waitingState = waitingState, waitingState != .extraction {
            // During waiting states (except extraction), restrict to empty set
            // Extraction is special: tools stay enabled for dossier question collection
            tools = []
        } else {
            // No waiting state OR extraction state - use normal phase-based tools
            tools = getAllowedToolsForCurrentPhase()
        }

        // Avoid duplicate emissions - only publish if tools actually changed
        if tools == lastPublishedTools {
            return
        }
        lastPublishedTools = tools

        await emit(.stateAllowedToolsUpdated(tools: tools))

        // Log after emitting
        if let waitingState = waitingState, waitingState != .extraction {
            Logger.info("🚫 ALL TOOLS GATED - Waiting for user input (state: \(waitingState.rawValue))", category: .ai)
            let normalTools = getAllowedToolsForCurrentPhase()
            if !normalTools.isEmpty {
                Logger.info("   ⛔️ Blocked tools (\(normalTools.count)): \(normalTools.sorted().joined(separator: ", "))", category: .ai)
            }
        } else if tools.isEmpty {
            Logger.info("🔧 No tools available in current phase", category: .ai)
        } else if waitingState == .extraction {
            Logger.info("🔧 Tools enabled during extraction (\(tools.count)): allowing dossier questions", category: .ai)
        } else {
            Logger.info("🔧 Tools enabled (\(tools.count)): \(tools.sorted().joined(separator: ", "))", category: .ai)
        }
    }
    /// Get allowed tools for the current phase, minus any excluded tools
    private func getAllowedToolsForCurrentPhase() -> Set<String> {
        let phaseTools = phasePolicy.allowedTools[currentPhase] ?? []
        return phaseTools.subtracting(excludedTools)
    }
    /// Public API to trigger tool permission republication
    func publishToolPermissionsNow() async {
        await publishToolPermissions()
    }

    /// Snapshot the currently effective allowed tools set (after waiting-state gating).
    /// This is used during session resume to avoid relying on `stateAllowedToolsUpdated`
    /// events that may have been emitted before subscribers were attached.
    func getEffectiveAllowedToolsSnapshot() -> Set<String> {
        if let waitingState = waitingState, waitingState != .extraction {
            return []
        }
        return getAllowedToolsForCurrentPhase()
    }
    /// Update excluded tools and republish permissions
    func setExcludedTools(_ tools: Set<String>) async {
        excludedTools = tools
        await publishToolPermissions()
    }
    /// Add a tool to the excluded set
    func excludeTool(_ toolName: String) async {
        excludedTools.insert(toolName)
        await publishToolPermissions()
    }
    /// Remove a tool from the excluded set
    func includeTool(_ toolName: String) async {
        excludedTools.remove(toolName)
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
        excludedTools = []
        // Reset KC validation queue
        pendingKCValidationQueue = []
        isAutoValidation = false
        // Reset sync caches
        isProcessingSync = false
        isActiveSync = false
        pendingExtractionSync = nil
        pendingStreamingStatusSync = nil
        Logger.info("🔄 SessionUIState reset", category: .ai)
    }
}
