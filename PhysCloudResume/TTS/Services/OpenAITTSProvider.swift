import AVFoundation
import Foundation

/// Provides Text-to-Speech functionality using the OpenAI API
@MainActor
class OpenAITTSProvider {
    /// Available voices for TTS
    enum Voice: String, CaseIterable {
        case alloy
        case echo
        case fable
        case onyx
        case nova
        case shimmer

        /// Returns a user-friendly display name for the voice
        var displayName: String {
            switch self {
            case .alloy: return "Alloy (Neutral)"
            case .echo: return "Echo (Male)"
            case .fable: return "Fable (British)"
            case .onyx: return "Onyx (Deep Male)"
            case .nova: return "Nova (Female)"
            case .shimmer: return "Shimmer (Soft Female)"
            }
        }
    }

    /// The OpenAI client to use for TTS
    ///
    private let client: OpenAIClientProtocol
    /// Token that identifies the currently active streaming request.
    private var currentStreamID: UUID?
    /// Marks the active request as cancelled so late chunks are ignored.
    private var streamCancelled = false
    /// The audio player for playing audio
    private var audioPlayer: AVAudioPlayer?
    /// Strong reference so the delegate isn’t deallocated immediately
    private var audioPlayerDelegate: AudioPlayerDelegate?
    /// Tracks if the current streaming has been cancelled to ignore further chunks
    private var cancelRequested: Bool = false
    /// Unique identifier for the active streaming session
    private var streamToken: UUID?

    // MARK: - Playback state callbacks (wired to UI)

    /// Fires when the first audio buffer starts playing (leaves buffering state).
    var onReady: (() -> Void)?
    /// Fires when playback finishes naturally or is stopped.
    var onFinish: (() -> Void)?
    /// Fires when any playback/streaming error occurs.
    var onError: ((Error) -> Void)?

    // Adapter-based streaming player using ChunkedAudioPlayer
    private let streamer = TTSAudioStreamer()

    /// Initializes a new TTS provider with a specific API key
    /// - Parameter apiKey: The OpenAI API key to use
    init(apiKey: String) {
        // Always use MacPaw client as SwiftOpenAI doesn't support TTS
        client = OpenAIClientFactory.createTTSClient(apiKey: apiKey)
    }

    /// Initializes a new TTS provider with a pre-configured client
    /// - Parameter client: The OpenAI client to use
    init(client: OpenAIClientProtocol) {
        self.client = client
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
                case let .failure(error):
                    if !self.cancelRequested {
                        print("TTS streaming error: \(error)")
                    }
                }
            },
            onComplete: onComplete
        )
    }

    /// Stops the currently playing speech and cancels any ongoing streaming
    func stopSpeaking() {
        // mark any existing stream as cancelled
        streamCancelled = true
        currentStreamID = nil

        audioPlayer?.stop()
        audioPlayer = nil

        streamer.stop()
        onFinish?()
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
        stopSpeaking() // hard reset

        // ---- fresh stream token ----
        let streamID = UUID()
        currentStreamID = streamID
        streamCancelled = false

        // Wire up callbacks to drive UI state.
        streamer.onReady = { [weak self] in
            DispatchQueue.main.async {
                self?.onReady?()
                onStart?()
            }
        }
        streamer.onFinish = { [weak self] in
            DispatchQueue.main.async {
                self?.onFinish?()
                onComplete(nil)
            }
        }
        streamer.onError = { [weak self] error in
            DispatchQueue.main.async {
                self?.onError?(error)
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
                case let .success(data): self.streamer.append(data)
                case let .failure(error): self.streamer.onError?(error)
                }
            },
            onComplete: { [weak self] error in
                guard let self, self.currentStreamID == streamID else { return }
                if let error = error { self.streamer.onError?(error) }
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
        stopSpeaking()
        onFinish?()
    }
}
