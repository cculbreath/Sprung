import AVFoundation
import Foundation

/// Provides Text-to-Speech functionality using the OpenAI API
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
    private let client: OpenAIClientProtocol

    /// The audio player for playing audio
    private var audioPlayer: AVAudioPlayer?

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
        client.sendTTSRequest(text: text, voice: voice.rawValue, instructions: instructions) { [weak self] result in
            switch result {
            case let .success(audioData):
                self?.playAudio(audioData, onComplete: onComplete)
            case let .failure(error):
                onComplete(error)
            }
        }
    }

    /// Converts text to speech with streaming
    /// - Parameters:
    ///   - text: The text to convert to speech
    ///   - voice: The voice to use
    ///   - instructions: Custom voice instructions (optional)
    ///   - onChunk: Called for each received audio chunk
    ///   - onComplete: Called when streaming is complete
    func streamText(_ text: String, voice: Voice = .nova, instructions: String? = nil, onChunk: @escaping (Data) -> Void, onComplete: @escaping (Error?) -> Void) {
        client.sendTTSStreamingRequest(text: text, voice: voice.rawValue, instructions: instructions, onChunk: { result in
            switch result {
            case let .success(audioData):
                onChunk(audioData)
            case let .failure(error):
                print("TTS streaming error: \(error)")
            }
        }, onComplete: onComplete)
    }

    /// Stops the currently playing speech
    func stopSpeaking() {
        audioPlayer?.stop()
        audioPlayer = nil
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
            audioPlayer?.delegate = AudioPlayerDelegate(onComplete: onComplete)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            onComplete(error)
        }
    }

    /// Delegate for audio player completion
    private class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
        private let onComplete: (Error?) -> Void

        init(onComplete: @escaping (Error?) -> Void) {
            self.onComplete = onComplete
            super.init()
        }

        func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully flag: Bool) {
            onComplete(flag ? nil : NSError(domain: "OpenAITTSProvider", code: 2000, userInfo: [NSLocalizedDescriptionKey: "Audio playback failed"]))
        }

        func audioPlayerDecodeErrorDidOccur(_: AVAudioPlayer, error: Error?) {
            onComplete(error ?? NSError(domain: "OpenAITTSProvider", code: 2001, userInfo: [NSLocalizedDescriptionKey: "Audio decode error"]))
        }
    }
}
