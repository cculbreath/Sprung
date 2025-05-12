//
//  TTSViewModel.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/24/25.
//

import Combine
import Foundation
import Observation

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
        print("[TTSViewModel] Initialized with provider.")
        setupCallbacks()
    }

    // MARK: - Setup

    /// Configures callbacks from the TTS provider to update view model state
    private func setupCallbacks() {
        print("[TTSViewModel] Setting up callbacks.")
        // Update buffering state when it changes in the provider
        ttsProvider.onBufferingStateChanged = { [weak self] buffering in
            guard let self = self else { return }
            print("[TTSViewModel] Provider onBufferingStateChanged: \(buffering). Current isInitialSetup: \(self.isInitialSetup)")

            if !self.isInitialSetup || buffering {
                let oldValue = self.isBuffering
                self.isBuffering = buffering
                print("[TTSViewModel] Buffering state changed: \(oldValue) -> \(buffering)")
                self.logCurrentState("after provider buffering update")
            } else {
                print("[TTSViewModel] Ignored provider buffering state change during initial setup.")
            }
        }

        // Handle playback ready state (buffering complete, playback starting)
        ttsProvider.onReady = { [weak self] in
            guard let self = self else { return }
            print("[TTSViewModel] Provider onReady callback.")
            self.isInitialSetup = false // Clear initial setup flag
            self.isBuffering = false
            self.isSpeaking = true
            self.isPaused = false
            print("[TTSViewModel] Playback ready (from provider onReady).")
            self.logCurrentState("after provider onReady")
        }

        // Handle playback completion
        ttsProvider.onFinish = { [weak self] in
            guard let self = self else { return }
            print("[TTSViewModel] Provider onFinish callback. Current isInitialSetup: \(self.isInitialSetup)")
            if self.isInitialSetup {
                print("[TTSViewModel] Ignoring provider finish event during initial setup.")
                return
            }
            self.isSpeaking = false
            self.isPaused = false
            self.isBuffering = false
            print("[TTSViewModel] Playback finished (from provider onFinish).")
            self.logCurrentState("after provider onFinish")
        }

        // Handle playback errors
        ttsProvider.onError = { [weak self] error in
            guard let self = self else { return }
            print("[TTSViewModel] Provider onError callback: \(error.localizedDescription)")
            self.isInitialSetup = false // Clear initial setup on error
            self.ttsError = error.localizedDescription
            self.isBuffering = false
            self.isSpeaking = false
            self.isPaused = false
            print("[TTSViewModel] Error from provider: \(error.localizedDescription)")
            self.logCurrentState("after provider onError")
        }
    }

    /// Log current state for debugging
    private func logCurrentState(_ context: String) {
        print("TTS VM STATE [\(context)]: speaking=\(isSpeaking), paused=\(isPaused), buffering=\(isBuffering), isInitialSetup=\(isInitialSetup)")
    }

    // MARK: - Public Methods

    /// Starts playback of the provided content
    /// - Parameters:
    ///   - content: The text content to speak
    ///   - voice: The voice to use for speech
    ///   - instructions: Optional voice tuning instructions
    func speakContent(_ content: String, voice: OpenAITTSProvider.Voice, instructions: String?) {
        print("[TTSViewModel] speakContent called. Content empty: \(content.isEmpty)")
        logCurrentState("at start of speakContent")

        guard !content.isEmpty else {
            ttsError = "No content to speak"
            print("[TTSViewModel] Error: No content to speak.")
            logCurrentState("after no content error")
            return
        }

        stop() // Reset any ongoing playback and state FIRST

        isInitialSetup = true // Set initial setup flag
        print("[TTSViewModel] isInitialSetup set to true.")

        // Perform state updates on the main actor
        Task { @MainActor in
            self.isSpeaking = false
            self.isPaused = false
            self.isBuffering = true // Immediately go to buffering
            print("[TTSViewModel] Set directly to buffering state (isSpeaking=false, isPaused=false, isBuffering=true).")
            self.logCurrentState("after setting buffering state in speakContent")
        }

        let cleanContent = content
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")

        print("[TTSViewModel] Starting ttsProvider.streamAndPlayText (isInitialSetup is true).")

        // No artificial delay needed here if state updates are correctly managed.
        // The provider's callbacks will handle transitions out of buffering.
        ttsProvider.streamAndPlayText(
            cleanContent,
            voice: voice,
            instructions: instructions,
            onStart: { // This is onReady from the provider
                print("[TTSViewModel] ttsProvider.streamAndPlayText onStart callback received.")
                // State changes are handled by the provider's onReady callback.
            },
            onComplete: { error in // This is onFinish/onError from the provider
                print("[TTSViewModel] ttsProvider.streamAndPlayText onComplete callback received. Error: \(error?.localizedDescription ?? "none")")
                // State changes are handled by the provider's onFinish/onError callbacks.
            }
        )
    }

    /// Pauses current playback if playing
    func pause() {
        print("[TTSViewModel] pause called.")
        if ttsProvider.pause() { // ttsProvider.pause() returns true if it successfully paused
            isSpeaking = false
            isPaused = true
            isBuffering = false
            print("[TTSViewModel] Playback paused.")
            logCurrentState("after pause")
        } else {
            print("[TTSViewModel] Pause command ignored or failed.")
        }
    }

    /// Resumes playback if paused
    func resume() {
        print("[TTSViewModel] resume called.")
        if ttsProvider.resume() { // ttsProvider.resume() returns true if it successfully resumed
            isSpeaking = true
            isPaused = false
            isBuffering = false
            print("[TTSViewModel] Playback resumed.")
            logCurrentState("after resume")
        } else {
            print("[TTSViewModel] Resume command ignored or failed.")
        }
    }

    /// Stops playback completely, resetting all state
    func stop() {
        print("[TTSViewModel] stop called.")
        ttsProvider.stopSpeaking() // This should trigger onFinish or onError in the provider

        // Manually reset state here to ensure UI consistency immediately,
        // especially if provider callbacks are delayed or missed.
        Task { @MainActor in
            self.isInitialSetup = false
            self.isSpeaking = false
            self.isPaused = false
            self.isBuffering = false
            print("[TTSViewModel] Playback stopped, state reset.")
            self.logCurrentState("after stop")
        }
    }
}
