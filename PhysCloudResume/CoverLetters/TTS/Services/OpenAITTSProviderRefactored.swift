// PhysCloudResume/CoverLetters/TTS/Services/OpenAITTSProviderRefactored.swift

import AVFoundation
import Foundation
import os.log
import SwiftUI
import SwiftOpenAI

/// Refactored TTS provider with better separation of concerns
class OpenAITTSProviderRefactored {
    
    // MARK: - Voice Enumeration (preserved from original)
    
    enum Voice: String, CaseIterable {
        case alloy, ash, ballad, coral, echo, fable, onyx, nova, sage, shimmer, verse
        
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
    
    // MARK: - Properties
    
    private let ttsClient: TTSCapable
    private let audioManager: TTSAudioManager
    private let streamingManager: TTSStreamingManager
    private let stateManager: TTSStateManager
    
    // MARK: - Public Callbacks
    
    var apiKey: String?
    var onReady: (() -> Void)? {
        didSet {
            audioManager.onReady = onReady
            streamingManager.onReady = onReady
        }
    }
    var onFinish: (() -> Void)? {
        didSet {
            audioManager.onFinish = onFinish
            streamingManager.onFinish = onFinish
        }
    }
    var onError: ((Error) -> Void)? {
        didSet {
            audioManager.onError = onError
            streamingManager.onError = onError
            stateManager.onError = onError
        }
    }
    var onBufferingStateChanged: ((Bool) -> Void)? {
        didSet {
            stateManager.onBufferingStateChanged = onBufferingStateChanged
        }
    }
    
    // MARK: - Initialization
    
    init(apiKey: String) {
        self.apiKey = apiKey
        
        // Initialize state manager first
        self.stateManager = TTSStateManager()
        
        // Initialize audio and streaming managers
        self.audioManager = TTSAudioManager()
        self.streamingManager = TTSStreamingManager(stateManager: stateManager)
        
        // Initialize TTS client
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanKey.isEmpty || cleanKey == "none" {
            Logger.warning("🚨 Creating TTS provider with empty API key - TTS will be disabled")
            ttsClient = PlaceholderTTSClient(errorMessage: "TTS service unavailable - invalid OpenAI API key")
        } else {
            Logger.debug("🔑 Creating dedicated OpenAI TTS client with API key: \(cleanKey.prefix(4))..., length: \(cleanKey.count)")
            let openAIClient = OpenAIServiceFactory.service(apiKey: apiKey)
            ttsClient = OpenAIServiceTTSWrapper(service: openAIClient)
            Logger.debug("✅ OpenAI TTS client created successfully via wrapper")
        }
    }
    
    // MARK: - Public Interface
    
    /// Converts text to speech and plays it (simple mode)
    /// - Parameters:
    ///   - text: The text to convert to speech
    ///   - voice: The voice to use
    ///   - instructions: Custom voice instructions (optional)
    ///   - onComplete: Called when audio playback is complete or fails
    func speakText(_ text: String, voice: Voice = .nova, instructions: String? = nil, onComplete: @escaping (Error?) -> Void) {
        let processedText = TTSTextProcessor.prepareTextForTTS(text)
        
        guard !processedText.isEmpty else {
            onComplete(NSError(domain: "OpenAITTSProviderRefactored", code: 1001, 
                             userInfo: [NSLocalizedDescriptionKey: "Empty text provided for TTS"]))
            return
        }
        
        // Use audio manager for simple playback
        ttsClient.sendTTSRequest(
            text: processedText,
            voice: voice.rawValue,
            instructions: instructions,
            onComplete: { [weak self] result in
                switch result {
                case let .success(audioData):
                    self?.audioManager.playAudio(audioData, onComplete: onComplete)
                case let .failure(error):
                    onComplete(error)
                }
            }
        )
    }
    
    /// Streams TTS audio and plays it as chunks arrive (streaming mode)
    /// - Parameters:
    ///   - text: The text to speak
    ///   - voice: Desired OpenAI voice
    ///   - instructions: Optional voice-tuning instructions
    ///   - onStart: Called once the player is ready (buffering complete)
    ///   - onComplete: Called when playback finishes or errors
    func streamAndPlayText(
        _ text: String,
        voice: Voice = .nova,
        instructions: String? = nil,
        onStart: (() -> Void)? = nil,
        onComplete: @escaping (Error?) -> Void
    ) {
        let processedText = TTSTextProcessor.prepareTextForTTS(text)
        
        guard !processedText.isEmpty else {
            onComplete(NSError(domain: "OpenAITTSProviderRefactored", code: 1001,
                             userInfo: [NSLocalizedDescriptionKey: "Empty text provided for TTS"]))
            return
        }
        
        // Check if text needs chunking
        if TTSTextProcessor.requiresChunking(processedText) {
            let chunks = TTSTextProcessor.splitTextIntoChunks(processedText)
            Logger.info("🎵 Starting multi-chunk TTS streaming with \(chunks.count) chunks")
            
            streamingManager.streamMultipleChunks(
                chunks,
                voice: voice.rawValue,
                instructions: instructions,
                ttsClient: ttsClient,
                onStart: onStart,
                onComplete: onComplete
            )
        } else {
            // Single chunk - use streaming manager
            streamingManager.streamSingleChunk(
                processedText,
                voice: voice.rawValue,
                instructions: instructions,
                ttsClient: ttsClient,
                onStart: onStart,
                onComplete: onComplete
            )
        }
    }
    
    /// Stops the currently playing speech and cancels any ongoing streaming
    func stopSpeaking() {
        stateManager.reset()
        audioManager.stopPlayback()
        streamingManager.stopStreaming()
    }
    
    // MARK: - Transport Controls
    
    /// Pause playback
    /// - Returns: True on success
    @discardableResult
    func pause() -> Bool {
        return streamingManager.pause() || audioManager.pause()
    }
    
    /// Resume playback
    /// - Returns: True on success
    @discardableResult
    func resume() -> Bool {
        return streamingManager.resume() || audioManager.resume()
    }
    
    // MARK: - Audio Access
    
    /// Get the complete cached audio data from streaming
    /// - Returns: The complete audio data or nil
    func getCachedAudio() -> Data? {
        return streamingManager.getCachedAudio()
    }
    
    /// Save the complete audio data to a file
    /// - Parameter url: The URL to save to
    /// - Returns: True if saving was successful
    func saveAudioToFile(url: URL) -> Bool {
        return streamingManager.saveAudioToFile(url: url)
    }
    
    // MARK: - State Queries
    
    /// Checks if currently buffering
    var isBuffering: Bool {
        return stateManager.isBuffering
    }
    
    /// Checks if audio is currently playing
    var isPlaying: Bool {
        return audioManager.isPlaying
    }
    
    /// Gets current playback time (for simple audio manager)
    var currentTime: TimeInterval {
        return audioManager.currentTime
    }
    
    /// Gets total duration (for simple audio manager)
    var duration: TimeInterval {
        return audioManager.duration
    }
    
    // MARK: - Text Analysis Utilities
    
    /// Estimates audio duration for text
    /// - Parameter text: The text to analyze
    /// - Returns: Estimated duration in seconds
    func estimateAudioDuration(_ text: String) -> TimeInterval {
        return TTSTextProcessor.estimateAudioDuration(text)
    }
    
    /// Gets word count for text
    /// - Parameter text: The text to analyze
    /// - Returns: Number of words
    func getWordCount(_ text: String) -> Int {
        return TTSTextProcessor.getWordCount(text)
    }
    
    // MARK: - Cleanup
    
    deinit {
        // Services handle their own cleanup through their deinit methods
        stateManager.clearCallbacks()
        audioManager.clearCallbacks()
        streamingManager.clearCallbacks()
    }
}