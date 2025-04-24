//
//  TTSViewModel.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/24/25.
//

import Foundation
import Combine

/// Handles text-to-speech state and operations, separating this logic from the view
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
            DispatchQueue.main.async {
                self?.isBuffering = buffering
                print("TTS VM: Buffering state changed: \(buffering)")
            }
        }
        
        // Handle playback ready state (buffering complete, playback starting)
        ttsProvider.onReady = { [weak self] in
            DispatchQueue.main.async {
                self?.isBuffering = false
                self?.isSpeaking = true
                self?.isPaused = false
                print("TTS VM: Playback ready")
            }
        }
        
        // Handle playback completion
        ttsProvider.onFinish = { [weak self] in
            DispatchQueue.main.async {
                self?.isSpeaking = false
                self?.isPaused = false
                self?.isBuffering = false
                print("TTS VM: Playback finished")
            }
        }
        
        // Handle playback errors
        ttsProvider.onError = { [weak self] error in
            DispatchQueue.main.async {
                self?.ttsError = error.localizedDescription
                self?.isBuffering = false
                self?.isSpeaking = false
                self?.isPaused = false
                print("TTS VM: Error: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Starts playback of the provided content
    /// - Parameters:
    ///   - content: The text content to speak
    ///   - voice: The voice to use for speech
    ///   - instructions: Optional voice tuning instructions
    func speakContent(_ content: String, voice: OpenAITTSProvider.Voice, instructions: String?) {
        // Reset state
        isSpeaking = false
        isPaused = false
        
        // Skip empty content
        guard !content.isEmpty else {
            ttsError = "No content to speak"
            return
        }
        
        // Clean content (remove basic markdown)
        let cleanContent = content
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
        
        print("TTS VM: Starting playback")
        
        // Start playback
        ttsProvider.streamAndPlayText(
            cleanContent,
            voice: voice,
            instructions: instructions,
            onComplete: { [weak self] error in
                if let error = error {
                    DispatchQueue.main.async {
                        self?.ttsError = error.localizedDescription
                        print("TTS VM: Playback error: \(error.localizedDescription)")
                    }
                }
            }
        )
    }
    
    /// Pauses current playback if playing
    func pause() {
        if ttsProvider.pause() {
            isSpeaking = false
            isPaused = true
            print("TTS VM: Playback paused")
        }
    }
    
    /// Resumes playback if paused
    func resume() {
        if ttsProvider.resume() {
            isSpeaking = true
            isPaused = false
            print("TTS VM: Playback resumed")
        }
    }
    
    /// Stops playback completely, resetting all state
    func stop() {
        ttsProvider.stopSpeaking()
        isSpeaking = false
        isPaused = false
        isBuffering = false
        print("TTS VM: Playback stopped")
    }
}