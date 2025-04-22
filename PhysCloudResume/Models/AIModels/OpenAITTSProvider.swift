import Foundation
import AVFoundation

/// Provides Text-to-Speech functionality using the OpenAI API
class OpenAITTSProvider {
    /// Available voices for TTS
    enum Voice: String, CaseIterable {
        case alloy = "alloy"
        case echo = "echo"
        case fable = "fable"
        case onyx = "onyx"
        case nova = "nova"
        case shimmer = "shimmer"
        
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
        self.client = OpenAIClientFactory.createTTSClient(apiKey: apiKey)
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
    ///   - onComplete: Called when audio playback is complete or fails
    func speakText(_ text: String, voice: Voice = .nova, onComplete: @escaping (Error?) -> Void) {
        client.sendTTSRequest(text: text, voice: voice.rawValue) { [weak self] result in
            switch result {
            case .success(let audioData):
                self?.playAudio(audioData, onComplete: onComplete)
            case .failure(let error):
                onComplete(error)
            }
        }
    }
    
    /// Converts text to speech with streaming
    /// - Parameters:
    ///   - text: The text to convert to speech
    ///   - voice: The voice to use
    ///   - onChunk: Called for each received audio chunk
    ///   - onComplete: Called when streaming is complete
    func streamText(_ text: String, voice: Voice = .nova, onChunk: @escaping (Data) -> Void, onComplete: @escaping (Error?) -> Void) {
        client.sendTTSStreamingRequest(text: text, voice: voice.rawValue, onChunk: { result in
            switch result {
            case .success(let audioData):
                onChunk(audioData)
            case .failure(let error):
                print("TTS streaming error: \(error)")
            }
        }, onComplete: onComplete)
    }
    
    /// Plays the audio data
    /// - Parameters:
    ///   - audioData: The audio data to play
    ///   - onComplete: Called when playback is complete or fails
    private func playAudio(_ audioData: Data, onComplete: @escaping (Error?) -> Void) {
        do {
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
        
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            onComplete(flag ? nil : NSError(domain: "OpenAITTSProvider", code: 2000, userInfo: [NSLocalizedDescriptionKey: "Audio playback failed"]))
        }
        
        func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
            onComplete(error ?? NSError(domain: "OpenAITTSProvider", code: 2001, userInfo: [NSLocalizedDescriptionKey: "Audio decode error"]))
        }
    }
}