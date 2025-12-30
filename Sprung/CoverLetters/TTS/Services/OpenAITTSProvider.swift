// swift-format-disable: UseExplicitSelf
//
//  OpenAITTSProvider.swift
//  Sprung
//
//
import AVFoundation
import Foundation
import os.log
import SwiftUI
import SwiftOpenAI // For the TTS functionality from your SwiftOpenAI fork
/// Provides Text-to-Speech functionality using the OpenAI API
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
    /// The TTS client to use for speech synthesis
    private let ttsClient: TTSCapable
    /// Token that identifies the currently active streaming request.
    private var currentStreamID: UUID?
    /// Marks the active request as cancelled so late chunks are ignored.
    private var streamCancelled = false
    /// The audio player for playing audio
    private var audioPlayer: AVAudioPlayer?
    private var streamTimeoutTimer: Timer?
    private let streamTimeout: TimeInterval = 30.0
    /// Strong reference so the delegate isn't deallocated immediately
    private var audioPlayerDelegate: AudioPlayerDelegate?
    private var isBufferingFlag: Bool = false
    /// Tracks if we're in streaming setup phase to prevent premature callbacks
    private var isInStreamSetup: Bool = false
    // MARK: - Playback State Callbacks
    var onReady: (() -> Void)?
    var onFinish: (() -> Void)?
    var onError: ((Error) -> Void)?
    var onBufferingStateChanged: ((Bool) -> Void)?
    private let streamer = TTSAudioStreamer()
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
                if buffering {
                    startTimeoutTimer()
                } else {
                    cancelTimeoutTimer()
                }
            }
        }
    }
    /// Initializes a new TTS provider with a TTSCapable client from LLMFacade
    /// - Parameter ttsClient: A TTSCapable client (typically from LLMFacade.createTTSClient())
    init(ttsClient: TTSCapable) {
        self.ttsClient = ttsClient
        Logger.debug("✅ OpenAI TTS provider initialized with injected TTSCapable client")
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
        cancelTimeoutTimer()
        streamTimeoutTimer = Timer.scheduledTimer(withTimeInterval: streamTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Logger.warning("Streaming request timed out after \(self.streamTimeout) seconds")
            // Force cleanup on timeout - must dispatch to MainActor
            Task { @MainActor in
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
    func speakText(_ text: String, voice: Voice = .nova, instructions _: String? = nil, onComplete: @escaping (Error?) -> Void) {
        // OpenAI TTS has a 4096 character limit
        let maxLength = 4096
        var textToSpeak = text
        if text.count > maxLength {
            Logger.warning("Text length (\(text.count)) exceeds TTS limit (\(maxLength)). Truncating...")
            let truncated = String(text.prefix(maxLength))
            if let lastSpace = truncated.lastIndex(of: " ") {
                textToSpeak = String(truncated[..<lastSpace]) + "..."
            } else {
                textToSpeak = truncated + "..."
            }
            Logger.debug("Truncated text to \(textToSpeak.count) characters")
        }
        // Call the TTS-capable client with the voice and instructions
        ttsClient.sendTTSRequest(
            text: textToSpeak,
            voice: voice.rawValue,
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
    /// Stops the currently playing speech and cancels any ongoing streaming
    func stopSpeaking() {
        cancelTimeoutTimer()
        streamCancelled = true
        currentStreamID = nil
        if let player = audioPlayer {
            player.stop()
            audioPlayer = nil
            audioPlayerDelegate = nil // Important: release the delegate to prevent leaks
        }
        streamer.stop()
        // Important: Only clear buffering if this is a user-triggered stop
        if !isInStreamSetup {
            Logger.debug("Normal stop, clearing buffering")
            setBufferingState(false)
            onFinish?()
        } else {
            Logger.debug("In stream setup, preserving buffering state")
        }
    }
    /// Plays the audio data
    /// - Parameters:
    ///   - audioData: The audio data to play
    ///   - onComplete: Called when playback is complete or fails
    private func playAudio(_ audioData: Data, onComplete: @escaping (Error?) -> Void) {
        do {
            stopSpeaking()
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
    // MARK: – Streaming playback (incremental)
    /// Splits text into chunks at sentence boundaries
    /// - Parameters:
    ///   - text: The text to split
    ///   - maxLength: Maximum length per chunk (default 4000 to leave buffer)
    /// - Returns: Array of text chunks
    private func splitTextIntoChunks(_ text: String, maxLength: Int = 4000) -> [String] {
        var chunks: [String] = []
        var currentChunk = ""
        // Split by sentences (basic approach - could be improved with NLP)
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        for sentence in sentences {
            let trimmedSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedSentence.isEmpty { continue }
            // Add back the punctuation if it was removed
            let fullSentence = trimmedSentence + ". "
            // If adding this sentence would exceed the limit, save current chunk and start new one
            if !currentChunk.isEmpty && currentChunk.count + fullSentence.count > maxLength {
                chunks.append(currentChunk.trimmingCharacters(in: .whitespaces))
                currentChunk = fullSentence
            } else {
                currentChunk += fullSentence
            }
        }
        if !currentChunk.isEmpty {
            chunks.append(currentChunk.trimmingCharacters(in: .whitespaces))
        }
        Logger.debug("Split text into \(chunks.count) chunks. Lengths: \(chunks.map { $0.count })")
        return chunks
    }
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
        // Split text into chunks if needed
        let textChunks = splitTextIntoChunks(text)
        if textChunks.count == 1 {
            streamSingleChunk(textChunks[0], voice: voice, instructions: instructions,
                             onStart: onStart, onComplete: onComplete)
        } else {
            Logger.info("🎵 Starting multi-chunk TTS streaming with \(textChunks.count) chunks")
            streamMultipleChunks(textChunks, voice: voice, instructions: instructions,
                                onStart: onStart, onComplete: onComplete)
        }
    }
    /// Streams multiple text chunks with seamless playback transitions
    private func streamMultipleChunks(
        _ chunks: [String],
        voice: Voice,
        instructions: String?,
        onStart: (() -> Void)?,
        onComplete: @escaping (Error?) -> Void
    ) {
        guard !chunks.isEmpty else {
            onComplete(nil)
            return
        }
        Logger.debug("🎵 Starting multi-chunk streaming: \(chunks.count) chunks")
        // Create a task to handle the sequential chunk processing
        Task {
            var chunkIndex = 0
            var hasStarted = false
            func playNextChunk() async {
                guard chunkIndex < chunks.count else {
                    Logger.info("✅ Multi-chunk TTS streaming completed")
                    onComplete(nil)
                    return
                }
                let currentChunk = chunks[chunkIndex]
                Logger.debug("🎵 Streaming chunk \(chunkIndex + 1)/\(chunks.count) (\(currentChunk.count) chars)")
                streamSingleChunk(
                    currentChunk,
                    voice: voice,
                    instructions: instructions,
                    onStart: hasStarted ? nil : onStart, // Only call onStart for the first chunk
                    onComplete: { error in
                        if let error = error {
                            Logger.error("❌ Chunk \(chunkIndex + 1) failed: \(error.localizedDescription)")
                            onComplete(error)
                            return
                        }
                        if !hasStarted {
                            hasStarted = true
                        }
                        chunkIndex += 1
                        // Small delay to ensure smooth transition between chunks
                        Task {
                            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                            await playNextChunk()
                        }
                    }
                )
            }
            await playNextChunk()
        }
    }
    /// Streams a single chunk of text using ChunkedAudioPlayer
    private func streamSingleChunk(
        _ text: String,
        voice: Voice,
        instructions _: String?,
        onStart: (() -> Void)?,
        onComplete: @escaping (Error?) -> Void
    ) {
        isInStreamSetup = true
        Logger.debug("Entering BUFFERING/SETUP phase")
        // Stop any existing playback - without clearing buffering
        stopSpeaking() // stopSpeaking checks isInStreamSetup
        let streamID = UUID()
        currentStreamID = streamID
        streamCancelled = false
        isBufferingFlag = true
        Logger.debug("Setting buffering state to TRUE")
        Task { @MainActor in
            self.onBufferingStateChanged?(true)
        }
        startTimeoutTimer()
        // Add a safety timeout that forces exit from setup state after 15 seconds
        // even if callbacks are missed
        Task {
            try? await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
            await MainActor.run {
                guard !Task.isCancelled else { return }
                if self.isInStreamSetup {
                    Logger.warning("Forcing exit from setup state after timeout")
                    self.isInStreamSetup = false
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
                self.cancelTimeoutTimer()
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
                self.isInStreamSetup = false
                Logger.error("Stream error: \(error.localizedDescription)")
                self.cancelTimeoutTimer() // Ensure timer is cancelled
                self.setBufferingState(false)
                // If it's a chunk overflow error, handle it gracefully by completing normally
                let nsError = error as NSError
                if nsError.domain == "TTSAudioStreamer" && nsError.code == 1002 {
                    Logger.debug("Handling chunk overflow gracefully - completing stream")
                    self.onFinish?()
                    onComplete(nil)
                } else {
                    self.onError?(error)
                    onComplete(error)
                }
            }
        }
        ttsClient.sendTTSStreamingRequest(
            text: text,
            voice: voice.rawValue,
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
    // MARK: - Transport Controls
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
}
// swift-format-enable: all
