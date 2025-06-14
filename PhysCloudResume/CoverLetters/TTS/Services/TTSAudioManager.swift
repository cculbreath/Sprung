// PhysCloudResume/CoverLetters/TTS/Services/TTSAudioManager.swift

import AVFoundation
import Foundation

/// Handles simple audio playback functionality for TTS
class TTSAudioManager {
    
    // MARK: - Properties
    
    private var audioPlayer: AVAudioPlayer?
    private var audioPlayerDelegate: AudioPlayerDelegate?
    
    // MARK: - Callbacks
    
    var onReady: (() -> Void)?
    var onFinish: (() -> Void)?
    var onError: ((Error) -> Void)?
    
    // MARK: - Public Methods
    
    /// Plays audio data using AVAudioPlayer
    /// - Parameters:
    ///   - audioData: The audio data to play
    ///   - onComplete: Called when playback is complete or fails
    func playAudio(_ audioData: Data, onComplete: @escaping (Error?) -> Void) {
        do {
            // Stop any existing playback
            stopPlayback()
            
            // Create and configure the new player
            audioPlayer = try AVAudioPlayer(data: audioData)
            audioPlayerDelegate = AudioPlayerDelegate(audioManager: self, onComplete: onComplete)
            audioPlayer?.delegate = audioPlayerDelegate
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            
            // Notify UI that playback started
            DispatchQueue.main.async { self.onReady?() }
            
        } catch {
            onComplete(error)
        }
    }
    
    /// Stops the current audio playback
    func stopPlayback() {
        if let player = audioPlayer {
            player.stop()
            audioPlayer = nil
            audioPlayerDelegate = nil
        }
    }
    
    /// Pauses the current audio playback
    /// - Returns: True if pause was successful
    @discardableResult
    func pause() -> Bool {
        guard let player = audioPlayer else { return false }
        player.pause()
        return true
    }
    
    /// Resumes the current audio playback
    /// - Returns: True if resume was successful
    @discardableResult
    func resume() -> Bool {
        guard let player = audioPlayer else { return false }
        player.play()
        return true
    }
    
    /// Checks if audio is currently playing
    var isPlaying: Bool {
        return audioPlayer?.isPlaying ?? false
    }
    
    /// Gets the current playback time
    var currentTime: TimeInterval {
        return audioPlayer?.currentTime ?? 0
    }
    
    /// Gets the total duration of the audio
    var duration: TimeInterval {
        return audioPlayer?.duration ?? 0
    }
    
    /// Sets the current playback time
    /// - Parameter time: The time to seek to
    func setCurrentTime(_ time: TimeInterval) {
        audioPlayer?.currentTime = time
    }
    
    // MARK: - Cleanup
    
    func clearCallbacks() {
        onReady = nil
        onFinish = nil
        onError = nil
    }
    
    deinit {
        stopPlayback()
        clearCallbacks()
    }
}

// MARK: - Audio Player Delegate

private class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    private let onComplete: (Error?) -> Void
    private weak var audioManager: TTSAudioManager?
    
    init(audioManager: TTSAudioManager, onComplete: @escaping (Error?) -> Void) {
        self.audioManager = audioManager
        self.onComplete = onComplete
        super.init()
    }
    
    func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            audioManager?.onFinish?()
        }
        onComplete(flag ? nil : NSError(domain: "TTSAudioManager",
                                        code: 2000,
                                        userInfo: [NSLocalizedDescriptionKey: "Audio playback failed"]))
    }
    
    func audioPlayerDecodeErrorDidOccur(_: AVAudioPlayer, error: Error?) {
        let err = error ?? NSError(domain: "TTSAudioManager",
                                   code: 2001,
                                   userInfo: [NSLocalizedDescriptionKey: "Audio decode error"])
        Task { @MainActor in
            audioManager?.onError?(err)
        }
        onComplete(err)
    }
}