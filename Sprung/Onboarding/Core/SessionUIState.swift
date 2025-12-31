import Foundation
import SwiftyJSON

// MARK: - Tool Gating Pure Function

/// Availability state for a specific tool
enum ToolAvailability {
    case available
    case blocked(reason: String)
}

/// Centralized tool gating logic (pure function - no side effects)
struct ToolGating {
    /// Determine tool availability based on session state
    /// - Parameters:
    ///   - toolName: Name of the tool to check
    ///   - waitingState: Current waiting state (nil if not waiting)
    ///   - phaseAllowedTools: Set of tools allowed in current phase
    ///   - excludedTools: Set of tools explicitly excluded (e.g., bootstrap tools)
    /// - Returns: Availability status with reason if blocked
    static func availability(
        for toolName: String,
        waitingState: SessionUIState.WaitingState?,
        phaseAllowedTools: Set<String>,
        excludedTools: Set<String>
    ) -> ToolAvailability {
        // Check if tool is excluded (e.g., one-time bootstrap tools)
        if excludedTools.contains(toolName) {
            return .blocked(reason: "Tool '\(toolName)' has been excluded")
        }

        // Check if tool is allowed in current phase
        guard phaseAllowedTools.contains(toolName) else {
            return .blocked(reason: "Tool '\(toolName)' is not available in the current phase")
        }

        // Handle waiting states
        if let waitingState = waitingState {
            switch waitingState {
            case .extraction:
                // During extraction, ALL phase-allowed tools remain enabled
                // This allows dossier question collection during PDF processing
                return .available

            case .validation:
                // During validation, only timeline tools are allowed for real-time card editing
                if OnboardingToolName.timelineTools.contains(toolName) {
                    return .available
                } else {
                    return .blocked(reason: "Cannot execute non-timeline tools while waiting for validation (state: \(waitingState.rawValue))")
                }

            case .selection, .upload, .processing, .documentCollection:
                // All tools blocked during these waiting states
                return .blocked(reason: "Cannot execute tools while waiting for user input (state: \(waitingState.rawValue))")
            }
        }

        // No waiting state - tool is available
        return .available
    }

    /// Get the set of available tools based on current state
    /// - Parameters:
    ///   - waitingState: Current waiting state (nil if not waiting)
    ///   - phaseAllowedTools: Set of tools allowed in current phase
    ///   - excludedTools: Set of tools explicitly excluded
    /// - Returns: Set of tool names that are currently available
    static func availableTools(
        waitingState: SessionUIState.WaitingState?,
        phaseAllowedTools: Set<String>,
        excludedTools: Set<String>
    ) -> Set<String> {
        // Fast path: if no waiting state, return phase tools minus exclusions
        guard let waitingState = waitingState else {
            return phaseAllowedTools.subtracting(excludedTools)
        }

        switch waitingState {
        case .extraction:
            // During extraction, all phase-allowed tools remain enabled (minus exclusions)
            return phaseAllowedTools.subtracting(excludedTools)

        case .validation:
            // During validation, only timeline tools are available
            return OnboardingToolName.timelineTools.intersection(phaseAllowedTools).subtracting(excludedTools)

        case .selection, .upload, .processing, .documentCollection:
            // All tools blocked during these waiting states
            return []
        }
    }
}

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
        case documentCollection  // Waiting for user to click "Done with Uploads"
    }
    private(set) var waitingState: WaitingState?
    // MARK: - Pending UI Prompts
    private(set) var pendingExtraction: OnboardingPendingExtraction?
    private(set) var pendingStreamingStatus: String?

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
        // Apply phase-specific initial exclusions
        applyPhaseExclusions(phase)
        // Re-publish tool permissions when phase changes
        await publishToolPermissions()
    }

    /// Apply phase-specific initial tool exclusions
    /// These tools are gated until specific user actions occur:
    /// - submit_for_validation: ungated + mandated when user clicks "Done with Timeline"
    /// - next_phase: ungated when user approves timeline validation
    private func applyPhaseExclusions(_ phase: InterviewPhase) {
        switch phase {
        case .phase1VoiceContext:
            // Gate submit_for_validation until user clicks "Done with Timeline"
            // Gate next_phase until user approves validation
            excludedTools = [
                OnboardingToolName.submitForValidation.rawValue,
                OnboardingToolName.nextPhase.rawValue
            ]
            Logger.info("🔒 Phase 1 tool gating: submit_for_validation and next_phase excluded until user actions", category: .ai)

        case .phase2CareerStory, .phase3EvidenceCollection, .phase4StrategicSynthesis, .complete:
            // Clear Phase 1 exclusions when entering new phases
            excludedTools = []
        }
    }
    // MARK: - Session State
    /// Set processing state
    func setProcessingState(_ processing: Bool, emitEvent: Bool = true) async {
        let didChange = isProcessing != processing
        isProcessing = processing
        guard emitEvent, didChange else { return }
        // Emit event for other coordinators only when the value changes
        await emit(.processingStateChanged(processing))
    }
    /// Set active state
    func setActiveState(_ active: Bool) async {
        isActive = active
    }
    // MARK: - Waiting State Management
    /// Set waiting state and publish tool permissions
    /// KEY: This service owns waiting state AND publishes tool permissions
    /// - Parameters:
    ///   - state: The waiting state, or nil to clear
    ///   - emitEvent: Whether to emit the waitingStateChanged event (default true).
    ///                Pass false when called from StateCoordinator event handler to avoid infinite loop.
    func setWaitingState(_ state: WaitingState?, emitEvent: Bool = true) async {
        let previousState = waitingState
        waitingState = state
        // Publish tool permissions based on new waiting state
        await publishToolPermissions()
        // Emit waiting state change event only if requested
        if emitEvent {
            await emit(.waitingStateChanged(state?.rawValue))
        }
        // Log state transition
        if let state = state {
            Logger.info("⏸️  ENTERING WAITING STATE: \(state.rawValue)", category: .ai)
        } else if let previousState = previousState {
            Logger.info("▶️  EXITING WAITING STATE (was: \(previousState.rawValue))", category: .ai)
        }
    }
    /// Get current waiting state
    func getWaitingState() -> WaitingState? {
        waitingState
    }
    // MARK: - Pending Prompts
    /// Set pending upload request
    func setPendingUpload(_ request: OnboardingUploadRequest?) async {
        let newWaitingState: WaitingState? = request != nil ? .upload : nil
        await setWaitingState(newWaitingState)
    }
    /// Set pending choice prompt
    func setPendingChoice(_ prompt: OnboardingChoicePrompt?) async {
        let newWaitingState: WaitingState? = prompt != nil ? .selection : nil
        await setWaitingState(newWaitingState)
    }
    /// Set pending validation prompt
    func setPendingValidation(_ prompt: OnboardingValidationPrompt?) async {
        // Only set waiting state for validation mode, not editor mode
        // Editor mode allows tools to continue (e.g., timeline card creation)
        let newWaitingState: WaitingState? = (prompt != nil && prompt?.mode == .validation) ? .validation : nil
        await setWaitingState(newWaitingState)
    }

    /// Set pending extraction
    /// - Parameters:
    ///   - extraction: The pending extraction state, or nil to clear
    ///   - emitEvent: Whether to emit the pendingExtractionUpdated event (default true).
    ///                Pass false when called from StateCoordinator event handler to avoid infinite loop.
    func setPendingExtraction(_ extraction: OnboardingPendingExtraction?, emitEvent: Bool = true) async {
        pendingExtraction = extraction
        let newWaitingState: WaitingState? = extraction != nil ? .extraction : nil
        await setWaitingState(newWaitingState, emitEvent: emitEvent)
        // Emit event only if requested (avoid loop when called from event handler)
        guard emitEvent else { return }
        await emit(.pendingExtractionUpdated(extraction))
    }
    /// Set streaming status
    func setStreamingStatus(_ status: String?) {
        pendingStreamingStatus = status
    }

    // MARK: - Document Collection State

    /// Set document collection active state
    /// When active, all tools are gated until user clicks "Done with Uploads"
    func setDocumentCollectionActive(_ active: Bool) async {
        let newWaitingState: WaitingState? = active ? .documentCollection : nil
        await setWaitingState(newWaitingState)
        if active {
            Logger.info("📂 Document collection mode activated - tools gated until 'Done with Uploads'", category: .ai)
        }
    }

    // MARK: - Tool Gating Logic
    // Tool Gating Strategy:
    // When the system enters a waiting state (upload, selection, validation, processing),
    // tools are gated to prevent the LLM from calling tools while waiting for user input.
    // This ensures:
    // 1. The LLM cannot make progress until the user responds
    // 2. Tool calls don't interfere with the UI continuation flow
    // 3. Clear state boundaries between AI processing and user interaction
    //
    // EXCEPTIONS:
    // - During extraction (.extraction state), tools remain ENABLED to allow
    //   dossier question collection during the "dead time" of PDF extraction (2+ minutes).
    // - During validation (.validation state), timeline tools remain ENABLED to allow
    //   real-time card creation/editing while user reviews other content.
    //
    // The gating is enforced at two levels:
    // 1. LLMMessenger: Filters tool schemas based on allowedTools from .stateAllowedToolsUpdated events
    // 2. ToolExecutionCoordinator: Validates tool availability before executing any tool call
    //
    // When the waiting state is cleared, normal phase-based tool permissions are restored.
    /// Publish tool permissions based on current waiting state and phase
    /// KEY METHOD: This is where SessionUIState publishes tool permissions
    private func publishToolPermissions() async {
        // Use centralized tool gating logic
        let phaseTools = phasePolicy.allowedTools[currentPhase] ?? []
        let tools = ToolGating.availableTools(
            waitingState: waitingState,
            phaseAllowedTools: phaseTools,
            excludedTools: excludedTools
        )

        // Avoid duplicate emissions - only publish if tools actually changed
        if tools == lastPublishedTools {
            return
        }
        lastPublishedTools = tools

        await emit(.stateAllowedToolsUpdated(tools: tools))

        // Log after emitting
        if let waitingState = waitingState {
            if tools.isEmpty {
                Logger.info("🚫 ALL TOOLS GATED - Waiting for user input (state: \(waitingState.rawValue))", category: .ai)
                if !phaseTools.isEmpty {
                    Logger.info("   ⛔️ Blocked tools (\(phaseTools.count)): \(phaseTools.sorted().joined(separator: ", "))", category: .ai)
                }
            } else if waitingState == .extraction {
                Logger.info("🔧 Tools enabled during extraction (\(tools.count)): allowing dossier questions", category: .ai)
            } else if waitingState == .validation {
                Logger.info("🔧 Timeline tools enabled during validation (\(tools.count)): allowing real-time card editing", category: .ai)
            }
        } else if tools.isEmpty {
            Logger.info("🔧 No tools available in current phase", category: .ai)
        } else {
            Logger.info("🔧 Tools enabled (\(tools.count)): \(tools.sorted().joined(separator: ", "))", category: .ai)
        }
    }

    /// Public API to trigger tool permission republication
    func publishToolPermissionsNow() async {
        await publishToolPermissions()
    }

    /// Snapshot the currently effective allowed tools set (after waiting-state gating).
    /// This is used during session resume to avoid relying on `stateAllowedToolsUpdated`
    /// events that may have been emitted before subscribers were attached.
    func getEffectiveAllowedToolsSnapshot() -> Set<String> {
        let phaseTools = phasePolicy.allowedTools[currentPhase] ?? []
        return ToolGating.availableTools(
            waitingState: waitingState,
            phaseAllowedTools: phaseTools,
            excludedTools: excludedTools
        )
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
        pendingExtraction = nil
        pendingStreamingStatus = nil
        excludedTools = []
        Logger.info("🔄 SessionUIState reset", category: .ai)
    }
}
