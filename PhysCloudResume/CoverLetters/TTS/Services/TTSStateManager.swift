// PhysCloudResume/CoverLetters/TTS/Services/TTSStateManager.swift

import Foundation

/// Manages complex state coordination for TTS operations
class TTSStateManager {
    
    // MARK: - State Properties
    
    private(set) var isBufferingFlag: Bool = false
    private(set) var isInStreamSetup: Bool = false
    private var streamTimeoutTimer: Timer?
    
    // MARK: - Configuration
    
    private let streamTimeout: TimeInterval = 30.0
    
    // MARK: - Callbacks
    
    var onBufferingStateChanged: ((Bool) -> Void)?
    var onTimeout: (() -> Void)?
    var onError: ((Error) -> Void)?
    
    // MARK: - State Management
    
    /// Sets the buffering state with safety checks
    /// - Parameter buffering: Whether we're buffering
    func setBufferingState(_ buffering: Bool) {
        // Critical safety check: Only allow buffering to be turned off when:
        // 1. We're explicitly calling this from the main playback start
        // 2. We're calling it from a user-triggered stop
        if !buffering && isInStreamSetup {
            Logger.debug("BLOCKED attempt to clear buffering during setup phase")
            return
        }
        
        if isBufferingFlag != buffering {
            isBufferingFlag = buffering
            Logger.debug("Buffering state changed to \(buffering)")
            
            Task { @MainActor in
                self.onBufferingStateChanged?(buffering)
            }
            
            // Manage timeout timer based on buffering state
            if buffering {
                startTimeoutTimer()
            } else {
                cancelTimeoutTimer()
            }
        }
    }
    
    /// Enters the stream setup phase
    func enterStreamSetup() {
        isInStreamSetup = true
        Logger.debug("Entering BUFFERING/SETUP phase")
        
        // Force buffering state to true during setup
        isBufferingFlag = true
        Task { @MainActor in
            self.onBufferingStateChanged?(true)
        }
        startTimeoutTimer()
        
        // Safety timeout to force exit from setup state
        startSafetyTimeout()
    }
    
    /// Exits the stream setup phase
    func exitStreamSetup() {
        if isInStreamSetup {
            isInStreamSetup = false
            Logger.debug("Exiting BUFFERING/SETUP phase")
        }
    }
    
    /// Checks if currently in stream setup phase
    var isInStreamSetupPhase: Bool {
        return isInStreamSetup
    }
    
    /// Checks if currently buffering
    var isBuffering: Bool {
        return isBufferingFlag
    }
    
    // MARK: - Timeout Management
    
    /// Starts the timeout timer for streaming operations
    func startTimeoutTimer() {
        cancelTimeoutTimer()
        
        streamTimeoutTimer = Timer.scheduledTimer(withTimeInterval: streamTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Logger.warning("Streaming request timed out after \(self.streamTimeout) seconds")
            
            Task { @MainActor in
                self.handleTimeout()
            }
        }
        
        Logger.debug("Started timeout timer: \(streamTimeout) seconds")
    }
    
    /// Cancels the timeout timer
    func cancelTimeout() {
        cancelTimeoutTimer()
    }
    
    private func cancelTimeoutTimer() {
        if streamTimeoutTimer != nil {
            Logger.debug("Cancelling timeout timer")
            streamTimeoutTimer?.invalidate()
            streamTimeoutTimer = nil
        }
    }
    
    /// Handles timeout events
    private func handleTimeout() {
        isInStreamSetup = false
        setBufferingState(false)
        
        let timeoutError = NSError(
            domain: "TTSStateManager",
            code: 3001,
            userInfo: [NSLocalizedDescriptionKey: "Streaming request timed out"]
        )
        
        Task { @MainActor in
            self.onTimeout?()
            self.onError?(timeoutError)
        }
    }
    
    /// Starts a safety timeout to prevent getting stuck in setup state
    private func startSafetyTimeout() {
        Task {
            try? await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
            
            await MainActor.run {
                guard !Task.isCancelled else { return }
                
                if self.isInStreamSetup {
                    Logger.warning("Forcing exit from setup state after safety timeout")
                    self.isInStreamSetup = false
                    
                    if self.isBufferingFlag {
                        let timeoutError = NSError(
                            domain: "TTSStateManager",
                            code: 3002,
                            userInfo: [NSLocalizedDescriptionKey: "Buffering timed out"]
                        )
                        self.setBufferingState(false)
                        Task { @MainActor in
                            self.onError?(timeoutError)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - State Queries
    
    /// Determines if buffering state can be cleared
    /// - Returns: True if it's safe to clear buffering
    func canClearBuffering() -> Bool {
        return !isInStreamSetup
    }
    
    /// Determines if finish callbacks should be processed
    /// - Returns: True if finish callbacks should be processed
    func shouldProcessFinish() -> Bool {
        return !isInStreamSetup
    }
    
    /// Gets a string representation of current state for debugging
    var stateDescription: String {
        return "Buffering: \(isBufferingFlag), Setup: \(isInStreamSetup), Timer: \(streamTimeoutTimer != nil)"
    }
    
    // MARK: - Cleanup
    
    /// Resets all state to initial values
    func reset() {
        Logger.debug("Resetting TTS state manager")
        
        cancelTimeoutTimer()
        isInStreamSetup = false
        
        if isBufferingFlag {
            setBufferingState(false)
        }
    }
    
    /// Clears all callback references
    func clearCallbacks() {
        onBufferingStateChanged = nil
        onTimeout = nil
        onError = nil
    }
    
    deinit {
        reset()
        clearCallbacks()
    }
}