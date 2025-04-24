//
//  TTSViewModel.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/24/25.
//

import Combine
import Foundation

/// Handles text-to-speech state and operations, separating this logic from the view
@MainActor // Add MainActor to entire class since it interacts with OpenAITTSProvider
class TTSViewModel: ObservableObject {
    // MARK: - Published Properties

    /// Whether audio is currently playing
    @Published var isSpeaking: Bool = false

    /// Whether audio playback is paused
    @Published var isPaused: Bool = false

    /// Whether audio is being buffered before playback starts
    @Published var isBuffering: Bool = false

    /// Most recent TTS error message, if any
    @Published var ttsError: String? = nil

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
        setupCallbacks()
    }

    // MARK: - Setup

    /// Configures callbacks from the TTS provider to update view model state
    private func setupCallbacks() {
        // Update buffering state when it changes in the provider
        ttsProvider.onBufferingStateChanged = { [weak self] buffering in
            guard let self = self else { return }

            // Only update if we're not in initial setup or if setting to true
            // (prevents flashing back to false during setup)
            if !self.isInitialSetup || buffering {
                let oldValue = self.isBuffering
                self.isBuffering = buffering
                print("TTS VM: Buffering state changed: \(oldValue) -> \(buffering)")
                self.logCurrentState("after buffering update")
            } else {
                print("TTS VM: Ignored buffering state change during initial setup")
            }
        }

        // Handle playback ready state (buffering complete, playback starting)
        ttsProvider.onReady = { [weak self] in
            guard let self = self else { return }

            // Clear initial setup flag when audio is ready to play
            self.isInitialSetup = false

            self.isBuffering = false
            self.isSpeaking = true
            self.isPaused = false
            print("TTS VM: Playback ready")
            self.logCurrentState("after ready")
        }

        // Handle playback completion
        ttsProvider.onFinish = { [weak self] in
            guard let self = self else { return }

            // Skip finish events during initial setup
            if self.isInitialSetup {
                print("TTS VM: Ignoring finish event during initial setup")
                return
            }

            self.isSpeaking = false
            self.isPaused = false
            self.isBuffering = false
            print("TTS VM: Playback finished")
            self.logCurrentState("after finish")
        }

        // Handle playback errors
        ttsProvider.onError = { [weak self] error in
            guard let self = self else { return }

            // Always process errors, but clear setup flag
            self.isInitialSetup = false

            self.ttsError = error.localizedDescription
            self.isBuffering = false
            self.isSpeaking = false
            self.isPaused = false
            print("TTS VM: Error: \(error.localizedDescription)")
            self.logCurrentState("after error")
        }
    }

    /// Log current state for debugging
    private func logCurrentState(_ context: String) {
        print("TTS VM STATE [\(context)]: speaking=\(isSpeaking), paused=\(isPaused), buffering=\(isBuffering)")
    }

    // MARK: - Public Methods

    /// Starts playback of the provided content
    /// - Parameters:
    ///   - content: The text content to speak
    ///   - voice: The voice to use for speech
    ///   - instructions: Optional voice tuning instructions
    func speakContent(_ content: String, voice: OpenAITTSProvider.Voice, instructions: String?) {
        // Skip empty content check first
        guard !content.isEmpty else {
            ttsError = "No content to speak"
            return
        }

        // Reset any ongoing playback
        stop()

        // Set initial setup flag to prevent premature state changes
        isInitialSetup = true

        // Do state updates in a Task to ensure they're batched
        Task { @MainActor in
            // Reset state and immediately go to buffering
            isSpeaking = false
            isPaused = false
            isBuffering = true

            print("TTS VM: Set directly to buffering state")
            logCurrentState("after entering buffering state")
        }

        // Clean content (remove basic markdown)
        let cleanContent = content
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")

        print("TTS VM: Starting playback (in setup phase)")

        // Start playback with a slight delay to ensure state updates complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }

            self.ttsProvider.streamAndPlayText(
                cleanContent,
                voice: voice,
                instructions: instructions,
                onStart: { [weak self] in
                    print("TTS VM: Playback started")
                    // This is when audio begins playing (after buffering)
                    Task { @MainActor in
                        guard let self = self else { return }

                        // Clear initial setup flag when playback starts
                        self.isInitialSetup = false

                        // Transition to playing state
                        self.isBuffering = false
                        self.isSpeaking = true
                        self.logCurrentState("after starting playback")
                    }
                },
                onComplete: { [weak self] error in
                    guard let self = self else { return }

                    // Don't process completion during initial setup
                    // This prevents the flash to non-buffering state
                    if !self.isInitialSetup {
                        if let error = error {
                            Task { @MainActor in
                                self.ttsError = error.localizedDescription
                                self.isBuffering = false
                                self.isSpeaking = false
                                self.isPaused = false
                                print("TTS VM: Playback error: \(error.localizedDescription)")
                                self.logCurrentState("after error")
                            }
                        }
                    } else {
                        print("TTS VM: Ignoring completion callback during setup")
                    }
                }
            )
        }
    }

    /// Pauses current playback if playing
    func pause() {
        if ttsProvider.pause() {
            isSpeaking = false
            isPaused = true
            isBuffering = false // Make sure buffering is false when paused
            print("TTS VM: Playback paused")
            logCurrentState("after pause")
        }
    }

    /// Resumes playback if paused
    func resume() {
        if ttsProvider.resume() {
            isSpeaking = true
            isPaused = false
            isBuffering = false // Make sure buffering is false when resuming
            print("TTS VM: Playback resumed")
            logCurrentState("after resume")
        }
    }

    /// Stops playback completely, resetting all state
    func stop() {
        ttsProvider.stopSpeaking()
        Task { @MainActor in
            // Clear all state including setup flag
            isInitialSetup = false
            isSpeaking = false
            isPaused = false
            isBuffering = false
            print("TTS VM: Playback stopped")
            logCurrentState("after stop")
        }
    }
}
