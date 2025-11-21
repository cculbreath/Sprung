// swift-format-disable: UseExplicitSelf
//
//  TTSViewModel.swift
//  Sprung
//
//  Created by Christopher Culbreath on 4/24/25.
//
import Foundation
import Observation
import os.log
/// Handles text-to-speech state and operations, separating this logic from the view
@Observable
@MainActor // Add MainActor to entire class since it interacts with OpenAITTSProvider
class TTSViewModel {
    // MARK: - Properties
    /// Whether audio is currently playing
    var isSpeaking: Bool = false
    /// Whether audio playback is paused
    var isPaused: Bool = false
    /// Whether audio is being buffered before playback starts
    var isBuffering: Bool = false
    /// Most recent TTS error message, if any
    var ttsError: String?
    /// Timeout timer to prevent stuck states
    private var stateTimeoutTimer: Timer?
    // MARK: - Private Properties
    /// Flag to prevent premature state changes during streaming setup
    private var isInitialSetup: Bool = false
    /// The underlying TTS provider that handles streaming and playback
    private let ttsProvider: OpenAITTSProvider
    // MARK: - Initialization
    /// Creates a new TTS view model with the specified provider
    /// - Parameter ttsProvider: The TTS provider to use for speech synthesis
    init(ttsProvider: OpenAITTSProvider) {
        self.ttsProvider = ttsProvider
        Logger.info("🎤 [TTSViewModel] Initialized with provider")
        setupCallbacks()
    }
    deinit {
        Logger.debug("[TTSViewModel] Deinitializing")
        // Cancel any pending timeout timer and clear resources
        // using Task to ensure MainActor execution
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            // Cancel any pending timeout timer
            self.stateTimeoutTimer?.invalidate()
            self.stateTimeoutTimer = nil
            // Ensure playback is stopped
            self.stop()
            // Clear callback references to break potential cycles
            self.clearCallbacks()
        }
    }
    // MARK: - Setup
    /// Configures callbacks from the TTS provider to update view model state
    private func setupCallbacks() {
        Logger.info("🔧 [TTSViewModel] Setting up TTS callbacks")
        // Update buffering state when it changes in the provider
        ttsProvider.onBufferingStateChanged = { [weak self] buffering in
            guard let self = self else { return }
            Logger.debug("[TTSViewModel] Provider onBufferingStateChanged: \(buffering). Current isInitialSetup: \(self.isInitialSetup)")
            if !self.isInitialSetup || buffering {
                let oldValue = self.isBuffering
                self.isBuffering = buffering
                Logger.debug("[TTSViewModel] Buffering state changed: \(oldValue) -> \(buffering)")
                self.logCurrentState("after provider buffering update")
                // Set timeout for buffering state if it's turned on
                if buffering {
                    self.setStateTimeout(for: "buffering", duration: 15.0)
                } else {
                    self.clearStateTimeout()
                }
            } else {
                Logger.debug("[TTSViewModel] Ignored provider buffering state change during initial setup")
            }
        }
        // Handle playback ready state (buffering complete, playback starting)
        ttsProvider.onReady = { [weak self] in
            guard let self = self else { return }
            Logger.debug("[TTSViewModel] Provider onReady callback")
            self.isInitialSetup = false // Clear initial setup flag
            self.isBuffering = false
            self.isSpeaking = true
            self.isPaused = false
            self.clearStateTimeout() // Clear any timeout since we're now playing
            Logger.info("▶️ [TTSViewModel] Audio stream connected, playback started")
            self.logCurrentState("after provider onReady")
        }
        // Handle playback completion
        ttsProvider.onFinish = { [weak self] in
            guard let self = self else { return }
            Logger.debug("[TTSViewModel] Provider onFinish callback. Current isInitialSetup: \(self.isInitialSetup)")
            if self.isInitialSetup {
                Logger.debug("[TTSViewModel] Ignoring provider finish event during initial setup")
                return
            }

            // Special case: If we're still speaking or paused when onFinish is called, this is likely
            // from the chunk overflow handler, and we should NOT stop playback
            if (self.isSpeaking || self.isPaused) && !self.isBuffering {
                Logger.debug("[TTSViewModel] Received onFinish while speaking/paused - likely from chunk overflow handler, maintaining playback state")
                return
            }

            self.isSpeaking = false
            self.isPaused = false
            self.isBuffering = false
            self.clearStateTimeout() // Clear any timeout since we're done
            Logger.info("⏹️ [TTSViewModel] Playback completed successfully")
            self.logCurrentState("after provider onFinish")
        }
        // Handle playback errors
        ttsProvider.onError = { [weak self] error in
            guard let self = self else { return }
            Logger.debug("[TTSViewModel] Provider onError callback: \(error.localizedDescription)")
            self.isInitialSetup = false // Clear initial setup on error
            self.ttsError = error.localizedDescription
            self.isBuffering = false
            self.isSpeaking = false
            self.isPaused = false
            self.clearStateTimeout() // Clear any timeout since we're done
            Logger.debug("[TTSViewModel] Error from provider: \(error.localizedDescription)")
            self.logCurrentState("after provider onError")
        }
    }
    /// Clear all callbacks to break potential reference cycles
    private func clearCallbacks() {
        Logger.info("🧹 [TTSViewModel] Clearing TTS provider callbacks")
        ttsProvider.onBufferingStateChanged = nil
        ttsProvider.onReady = nil
        ttsProvider.onFinish = nil
        ttsProvider.onError = nil
    }
    /// Set a timeout to reset stuck states
    private func setStateTimeout(for state: String, duration: TimeInterval) {
        // Cancel any existing timeout
        clearStateTimeout()
        // Create new timeout
        stateTimeoutTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Logger.warning("[TTSViewModel] State timeout triggered for '\(state)' after \(duration) seconds")
            // If we're still in the timed out state, force reset
            // Execute on MainActor
            Task { @MainActor in
                guard !Task.isCancelled else { return }
                if (state == "buffering" && self.isBuffering) ||
                    (state == "speaking" && self.isSpeaking) {
                    self.isInitialSetup = false
                    self.isBuffering = false
                    self.isSpeaking = false
                    self.isPaused = false
                    self.ttsError = "Playback timed out"
                    // Ensure provider also resets
                    self.ttsProvider.stopSpeaking()
                    Logger.debug("[TTSViewModel] Forced state reset due to timeout")
                    self.logCurrentState("after timeout reset")
                }
            }
        }
    }
    /// Clear any active state timeout timer
    private func clearStateTimeout() {
        if stateTimeoutTimer != nil {
            Logger.debug("[TTSViewModel] Clearing state timeout timer")
            stateTimeoutTimer?.invalidate()
            stateTimeoutTimer = nil
        }
    }
    /// Log current state for debugging
    private func logCurrentState(_ context: String) {
        Logger
            .debug(
                "TTS VM STATE [\(context)]: speaking=\(self.isSpeaking), paused=\(self.isPaused), buffering=\(self.isBuffering), isInitialSetup=\(self.isInitialSetup)"
            )
    }
    // MARK: - Public Methods
    /// Starts playback of the provided content
    /// - Parameters:
    ///   - content: The text content to speak
    ///   - voice: The voice to use for speech
    ///   - instructions: Optional voice tuning instructions
    func speakContent(_ content: String, voice: OpenAITTSProvider.Voice, instructions: String?) {
        Logger.info("🎯 [TTSViewModel] Starting TTS playback. Content empty: \(content.isEmpty)")
        logCurrentState("at start of speakContent")
        guard !content.isEmpty else {
            ttsError = "No content to speak"
            Logger.warning("[TTSViewModel] Error: No content to speak")
            logCurrentState("after no content error")
            return
        }
        stop() // Reset any ongoing playback and state FIRST
        isInitialSetup = true // Set initial setup flag
        Logger.debug("[TTSViewModel] isInitialSetup set to true")
        // Perform state updates on the main actor
        Task { @MainActor in
            self.isSpeaking = false
            self.isPaused = false
            self.isBuffering = true // Immediately go to buffering
            Logger.debug("[TTSViewModel] Set directly to buffering state (isSpeaking=false, isPaused=false, isBuffering=true)")
            self.logCurrentState("after setting buffering state in speakContent")
            // Set timeout for the entire speak operation (30 seconds max)
            self.setStateTimeout(for: "speaking", duration: 30.0)
        }
        let cleanContent = content
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines) // Trim extra whitespace
        Logger.info("🌊 [TTSViewModel] Initiating audio stream for TTS content")
        // No artificial delay needed here if state updates are correctly managed.
        // The provider's callbacks will handle transitions out of buffering.
        // Implemented with weak self to prevent retain cycles
        ttsProvider.streamAndPlayText(
            cleanContent,
            voice: voice,
            instructions: instructions,
            onStart: { [weak self] in // This is onReady from the provider
                guard let _ = self else { return }
                Logger.debug("[TTSViewModel] ttsProvider.streamAndPlayText onStart callback received")
                // State changes are handled by the provider's onReady callback.
            },
            onComplete: { [weak self] error in // This is onFinish/onError from the provider
                guard let _ = self else { return }
                if let error = error {
                    Logger.error("[TTSViewModel] ttsProvider.streamAndPlayText onComplete received error: \(error.localizedDescription)")
                } else {
                    Logger.debug("[TTSViewModel] ttsProvider.streamAndPlayText onComplete received with no error")
                }
                // State changes are handled by the provider's onFinish/onError callbacks.
            }
        )
    }
    /// Pauses current playback if playing
    func pause() {
        Logger.debug("[TTSViewModel] pause called")
        if ttsProvider.pause() { // ttsProvider.pause() returns true if it successfully paused
            isSpeaking = false
            isPaused = true
            isBuffering = false
            // Clear any timeout since we're paused
            clearStateTimeout()
            Logger.info("⏸️ [TTSViewModel] Playback paused")
            logCurrentState("after pause")
        } else {
            Logger.debug("[TTSViewModel] Pause command ignored or failed")
        }
    }
    /// Resumes playback if paused
    func resume() {
        Logger.debug("[TTSViewModel] resume called")
        if ttsProvider.resume() { // ttsProvider.resume() returns true if it successfully resumed
            isSpeaking = true
            isPaused = false
            isBuffering = false
            // Set new timeout for the resumed playing state
            setStateTimeout(for: "speaking", duration: 30.0)
            Logger.info("▶️ [TTSViewModel] Playback resumed")
            logCurrentState("after resume")
        } else {
            Logger.debug("[TTSViewModel] Resume command ignored or failed")
        }
    }
    /// Stops playback completely, resetting all state
    func stop() {
        Logger.debug("[TTSViewModel] stop called")
        // Clear any timeout timer first
        clearStateTimeout()
        // Stop provider playback
        ttsProvider.stopSpeaking() // This should trigger onFinish or onError in the provider
        // Manually reset state here to ensure UI consistency immediately,
        // especially if provider callbacks are delayed or missed.
        Task { @MainActor in
            self.isInitialSetup = false
            self.isSpeaking = false
            self.isPaused = false
            self.isBuffering = false
            Logger.info("⏹️ [TTSViewModel] Playback stopped, state reset")
            self.logCurrentState("after stop")
        }
    }
}
// swift-format-enable: all
