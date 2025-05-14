// swift-format-disable: UseExplicitSelf

//
//  OpenAITTSProvider.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/22/25.
//

import AVFoundation
import Foundation
import os.log

/// Provides Text-to-Speech functionality using the OpenAI API
@MainActor
class OpenAITTSProvider {
    /// Available voices for TTS
    enum Voice: String, CaseIterable {
        case alloy
        case ash
        case ballad
        case coral
        case echo
        case fable
        case onyx
        case nova
        case sage
        case shimmer
        case verse

        /// Returns a user-friendly display name for the voice
        var displayName: String {
            switch self {
            case .alloy: return "Alloy (Female, Professional)"
            case .ash: return "Ash (Male, Authoritative)"
            case .ballad: return "Ballad (Male, Young British)"
            case .coral: return "Coral (Female, Expressive)"
            case .echo: return "Echo (Male, Engaging)"
            case .fable: return "Fable (Neutral, British Professional)"
            case .onyx: return "Onyx (Male, Professional)"
            case .nova: return "Nova (Female, Professional)"
            case .sage: return "Sage (Female, Engaging)"
            case .shimmer: return "Shimmer (Female, Authoritative)"
            case .verse: return "Verse (Neutral, Energetic)"
            }
        }
    }

    /// The OpenAI client to use for TTS
    ///
    private let client: OpenAIClientProtocol
    /// Logger for debugging TTS memory issues
    private static let logger = Logger()

    /// Token that identifies the currently active streaming request.
    private var currentStreamID: UUID?
    /// Marks the active request as cancelled so late chunks are ignored.
    private var streamCancelled = false
    /// The audio player for playing audio
    private var audioPlayer: AVAudioPlayer?

    /// Timeout timer to prevent stuck requests
    private var streamTimeoutTimer: Timer?
    /// Timeout duration for streaming requests (seconds)
    private let streamTimeout: TimeInterval = 30.0
    /// Strong reference so the delegate isn't deallocated immediately
    private var audioPlayerDelegate: AudioPlayerDelegate?
    /// Tracks if the current streaming has been cancelled to ignore further chunks
    private var cancelRequested: Bool = false
    /// Unique identifier for the active streaming session
    private var streamToken: UUID?
    /// Tracks if we're currently buffering audio
    private var isBufferingFlag: Bool = false

    /// Tracks if we're in streaming setup phase to prevent premature callbacks
    private var isInStreamSetup: Bool = false

    // MARK: - Playback state callbacks (wired to UI)

    /// Fires when the first audio buffer starts playing (leaves buffering state).
    var apiKey: String?
    var onReady: (() -> Void)?
    /// Fires when playback finishes naturally or is stopped.
    var onFinish: (() -> Void)?
    /// Fires when any playback/streaming error occurs.
    var onError: ((Error) -> Void)?
    /// Fires when buffering state changes
    var onBufferingStateChanged: ((Bool) -> Void)?

    // Adapter-based streaming player using ChunkedAudioPlayer
    private let streamer = TTSAudioStreamer()

    /// Returns the current buffering state
    var isBuffering: Bool {
        return isBufferingFlag
    }

    /// Set the buffering state and notify listeners
    private func setBufferingState(_ buffering: Bool) {
        // CRITICAL: Only allow buffering to be turned off when:
        // 1. We're explicitly calling this from the main playback start
        // 2. We're calling it from a user-triggered stop (like option-click)
        if !buffering, isInStreamSetup {
            Logger.debug("BLOCKED attempt to clear buffering during setup phase")
            return
        }

        if isBufferingFlag != buffering {
            isBufferingFlag = buffering
            Task { @MainActor in
                Logger.debug("Buffering state changed to \(buffering)")
                self.onBufferingStateChanged?(buffering)

                // If entering buffering, start timeout
                if buffering {
                    startTimeoutTimer()
                } else {
                    cancelTimeoutTimer()
                }
            }
        }
    }

    /// Initializes a new TTS provider with a specific API key
    /// - Parameter apiKey: The OpenAI API key to use
    init(apiKey: String) {
        self.apiKey = apiKey
        // Always use MacPaw client as SwiftOpenAI doesn't support TTS
        client = OpenAIClientFactory.createTTSClient(apiKey: apiKey)

        // Connect streamer buffering state to our provider
        streamer.onBufferingStateChanged = { [weak self] isBuffering in
            self?.setBufferingState(isBuffering)
        }

    }

    deinit {
        // Clean up all resources - must use Task to dispatch to the MainActor
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.cancelTimeoutTimer()
            self.clearCallbacks()
            self.stopSpeaking()
        }
    }

    /// Initializes a new TTS provider with a pre-configured client
    /// - Parameter client: The OpenAI client to use
    init(client: OpenAIClientProtocol) {
        self.client = client

        // Connect streamer buffering state to our provider
        streamer.onBufferingStateChanged = { [weak self] isBuffering in
            self?.setBufferingState(isBuffering)
        }

        Logger.debug("OpenAITTSProvider initialized with custom client")
    }

    /// Clear all callback references to break reference cycles
    private func clearCallbacks() {
        Logger.debug("Clearing all callbacks")
        onReady = nil
        onFinish = nil
        onError = nil
        onBufferingStateChanged = nil
    }

    /// Create and start a timeout timer for streaming operations
    private func startTimeoutTimer() {
        // First cancel any existing timer
        cancelTimeoutTimer()

        // Create a new timer
        streamTimeoutTimer = Timer.scheduledTimer(withTimeInterval: streamTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Logger.warning("Streaming request timed out after \(self.streamTimeout) seconds")

            // Force cleanup on timeout - must dispatch to MainActor
            Task { @MainActor in
                // Check if self is still alive
                guard !Task.isCancelled else { return }
                self.isInStreamSetup = false // Allow proper cleanup
                self.stopSpeaking()

                let timeoutError = NSError(domain: "OpenAITTSProvider", code: 3001,
                                           userInfo: [NSLocalizedDescriptionKey: "Streaming request timed out"])
                self.onError?(timeoutError)
            }
        }

        Logger.debug("Started timeout timer: \(streamTimeout) seconds")
    }

    /// Cancel the timeout timer if running
    private func cancelTimeoutTimer() {
        if streamTimeoutTimer != nil {
            Logger.debug("Cancelling timeout timer")
            streamTimeoutTimer?.invalidate()
            streamTimeoutTimer = nil
        }
    }

    /// Converts text to speech and plays it
    /// - Parameters:
    ///   - text: The text to convert to speech
    ///   - voice: The voice to use
    ///   - instructions: Custom voice instructions (optional)
    ///   - onComplete: Called when audio playback is complete or fails
    func speakText(_ text: String, voice: Voice = .nova, instructions: String? = nil, onComplete: @escaping (Error?) -> Void) {
        // Call the client with the voice and instructions
        client.sendTTSRequest(
            text: text,
            voice: voice.rawValue,
            instructions: instructions,
            onComplete: { [weak self] result in
                switch result {
                case let .success(audioData):
                    self?.playAudio(audioData, onComplete: onComplete)
                case let .failure(error):
                    onComplete(error)
                }
            }
        )
    }

    /// Converts text to speech with streaming
    /// - Parameters:
    ///   - text: The text to convert to speech
    ///   - voice: The voice to use
    ///   - instructions: Custom voice instructions (optional)
    ///   - onChunk: Called for each received audio chunk
    ///   - onComplete: Called when streaming is complete
    func streamText(_ text: String, voice: Voice = .nova, instructions: String? = nil, onChunk: @escaping (Data) -> Void, onComplete: @escaping (Error?) -> Void) {
        // Reset cancellation for this new streaming session
        cancelRequested = false
        // Call the client with the voice and instructions
        client.sendTTSStreamingRequest(
            text: text,
            voice: voice.rawValue,
            instructions: instructions,
            onChunk: { result in
                switch result {
                case let .success(audioData):
                    // Only forward chunks if not cancelled
                    if !self.cancelRequested {
                        onChunk(audioData)
                    }
                case .failure:
                    if !self.cancelRequested { Logger.debug("failure") }
                }
            },
            onComplete: onComplete
        )
    }

    /// Stops the currently playing speech and cancels any ongoing streaming
    func stopSpeaking() {
        // Cancel timeout timer first
        cancelTimeoutTimer()

        // mark any existing stream as cancelled
        streamCancelled = true
        currentStreamID = nil

        // Cleanup audio player
        if let player = audioPlayer {
            player.stop()
            audioPlayer = nil
            audioPlayerDelegate = nil // Important: release the delegate to prevent leaks
        }

        // Stop streamer
        streamer.stop()

        // Important: Only clear buffering if this is a user-triggered stop
        if !isInStreamSetup {
            Logger.debug("Normal stop, clearing buffering")
            setBufferingState(false)
            onFinish?()
        } else {
            Logger.debug("In stream setup, preserving buffering state")
            // Don't call onFinish
        }
    }

    /// Plays the audio data
    /// - Parameters:
    ///   - audioData: The audio data to play
    ///   - onComplete: Called when playback is complete or fails
    private func playAudio(_ audioData: Data, onComplete: @escaping (Error?) -> Void) {
        do {
            // Stop any existing playback
            stopSpeaking()

            // Create and configure the new player
            audioPlayer = try AVAudioPlayer(data: audioData)
            audioPlayerDelegate = AudioPlayerDelegate(provider: self, onComplete: onComplete)
            audioPlayer?.delegate = audioPlayerDelegate
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            // Notify UI that playback really started
            DispatchQueue.main.async { self.onReady?() }
        } catch {
            onComplete(error)
        }
    }

    /// Delegate for AVAudioPlayer completion/error handling
    private class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
        private let onComplete: (Error?) -> Void
        private weak var provider: OpenAITTSProvider?

        init(provider: OpenAITTSProvider, onComplete: @escaping (Error?) -> Void) {
            self.provider = provider
            self.onComplete = onComplete
            super.init()
        }

        func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully flag: Bool) {
            Task { @MainActor in
                provider?.onFinish?()
            }
            onComplete(flag ? nil : NSError(domain: "OpenAITTSProvider",
                                            code: 2000,
                                            userInfo: [NSLocalizedDescriptionKey: "Audio playback failed"]))
        }

        func audioPlayerDecodeErrorDidOccur(_: AVAudioPlayer, error: Error?) {
            let err = error ?? NSError(domain: "OpenAITTSProvider",
                                       code: 2001,
                                       userInfo: [NSLocalizedDescriptionKey: "Audio decode error"])
            Task { @MainActor in
                provider?.onError?(err)
            }
            onComplete(err)
        }
    }

    /// Plays raw audio data (e.g., after streaming)
    /// - Parameters:
    ///   - audioData: The full audio data to play
    ///   - onComplete: Called when playback is complete or fails
    func playAudioData(_ audioData: Data, onComplete: @escaping (Error?) -> Void) {
        playAudio(audioData, onComplete: onComplete)
    }

    // MARK: – Streaming playback (incremental)

    /// Streams TTS audio and plays it as chunks arrive using ChunkedAudioPlayer
    /// - Parameters:
    ///   - text: The text to speak.
    ///   - voice: Desired OpenAI voice.
    ///   - instructions: Optional voice‑tuning instructions.
    ///   - onStart: Called once the player is ready (buffering complete).
    ///   - onComplete: Called when playback finishes or errors.
    func streamAndPlayText(
        _ text: String,
        voice: Voice = .nova,
        instructions: String? = nil,
        onStart: (() -> Void)? = nil,
        onComplete: @escaping (Error?) -> Void
    ) {
        // Mark that we're in the BUFFERING/SETUP phase
        isInStreamSetup = true
        Logger.debug("Entering BUFFERING/SETUP phase")

        // Stop any existing playback - without clearing buffering
        stopSpeaking() // stopSpeaking checks isInStreamSetup

        // ---- fresh stream token ----
        let streamID = UUID()
        currentStreamID = streamID
        streamCancelled = false

        // Set initial buffering state to true (forced)
        isBufferingFlag = true
        Logger.debug("Setting buffering state to TRUE")

        // Notify listeners of buffering state
        Task { @MainActor in
            self.onBufferingStateChanged?(true)
        }

        // Start timeout timer
        startTimeoutTimer()

        // Add a safety timeout that forces exit from setup state after 15 seconds
        // even if callbacks are missed
        Task {
            try? await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
            // Move the actor-isolated work to the MainActor
            await MainActor.run {
                guard !Task.isCancelled else { return }
                if self.isInStreamSetup {
                    Logger.warning("Forcing exit from setup state after timeout")
                    self.isInStreamSetup = false

                    // If we're also still buffering, report an error
                    if self.isBufferingFlag {
                        let timeoutError = NSError(domain: "OpenAITTSProvider", code: 3002,
                                                   userInfo: [NSLocalizedDescriptionKey: "Buffering timed out"])
                        self.setBufferingState(false)
                        self.onError?(timeoutError)
                        onComplete(timeoutError)
                    }
                }
            }
        }

        // Wire up callbacks to drive UI state.
        streamer.onReady = { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }

                // This means audio is actually ready to play!
                // Exit setup phase and ALLOW exit from buffering
                self.isInStreamSetup = false
                Logger.debug("AUDIO READY - exiting setup phase")

                // Cancel timeout timer since audio is ready
                self.cancelTimeoutTimer()

                // Now it's safe to exit buffering state
                self.setBufferingState(false)
                self.onReady?()
                onStart?()
            }
        }
        streamer.onFinish = { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }

                // If we're in setup, DON'T clear buffering - we want
                // to maintain orange state until audio starts
                if self.isInStreamSetup {
                    Logger.debug("Ignoring finish during buffering setup")
                    return
                }

                Logger.debug("Stream finished normally")
                self.cancelTimeoutTimer() // Ensure timer is cancelled
                self.setBufferingState(false)
                self.onFinish?()
                onComplete(nil)
            }
        }
        streamer.onError = { [weak self] error in
            Task { @MainActor in
                guard let self = self else { return }

                // Always process errors
                self.isInStreamSetup = false
                Logger.error("Stream error: \(error.localizedDescription)")
                self.cancelTimeoutTimer() // Ensure timer is cancelled
                self.setBufferingState(false)
                self.onError?(error)
                onComplete(error)
            }
        }

        // Send streaming request and feed chunks to the adapter.
        client.sendTTSStreamingRequest(
            text: text,
            voice: voice.rawValue,
            instructions: instructions,
            onChunk: { [weak self] result in
                guard let self,
                      self.currentStreamID == streamID,
                      !self.streamCancelled else { return }

                switch result {
                case let .success(data):
                    Logger.debug("Received chunk of size \(data.count)")
                    self.streamer.append(data)
                case let .failure(error):
                    Logger.error("Chunk error: \(error.localizedDescription)")
                    self.streamer.onError?(error)
                }
            },
            onComplete: { [weak self] error in
                guard let self, self.currentStreamID == streamID else { return }
                if let error = error {
                    Logger.error("Streaming request error: \(error.localizedDescription)")
                    self.cancelTimeoutTimer()
                    self.setBufferingState(false)
                    self.streamer.onError?(error)
                }
            }
        )
    }

    // MARK: - External transport controls required by the UI

    // MARK: Transport controls

    /// Pause playback; returns `true` on success.
    @discardableResult
    func pause() -> Bool {
        if streamer.pause() { return true }
        if let player = audioPlayer {
            player.pause()
            return true
        }
        return false
    }

    /// Resume playback; returns `true` on success.
    @discardableResult
    func resume() -> Bool {
        if streamer.resume() { return true }
        if let player = audioPlayer {
            player.play() // AVAudioPlayer uses .play() to resume
            return true
        }
        return false
    }

    /// Stop completely (alias for previous `stopSpeaking()`).
    func stop() {
        // Clear the setup flag as this is a user-explicit stop
        isInStreamSetup = false
        Logger.debug("Explicit stop called")
        stopSpeaking()
        onFinish?()
    }
}

// swift-format-enable: all
