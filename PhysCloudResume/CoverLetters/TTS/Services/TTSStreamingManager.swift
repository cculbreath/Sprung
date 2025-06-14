// PhysCloudResume/CoverLetters/TTS/Services/TTSStreamingManager.swift

import Foundation

struct StreamingSession {
    let id: UUID
    var isCancelled: Bool = false
    let startTime: Date = Date()
}

/// Handles streaming TTS functionality with chunked audio playback
class TTSStreamingManager {
    
    // MARK: - Properties
    
    private let streamer = TTSAudioStreamer()
    private var currentSession: StreamingSession?
    private let stateManager: TTSStateManager
    
    // MARK: - Callbacks
    
    var onReady: (() -> Void)?
    var onFinish: (() -> Void)?
    var onError: ((Error) -> Void)?
    var onBufferingStateChanged: ((Bool) -> Void)?
    
    // MARK: - Initialization
    
    init(stateManager: TTSStateManager) {
        self.stateManager = stateManager
        setupStreamerCallbacks()
    }
    
    // MARK: - Public Methods
    
    /// Streams a single chunk of text
    /// - Parameters:
    ///   - text: The text to stream
    ///   - voice: The voice to use
    ///   - instructions: Optional voice instructions
    ///   - ttsClient: The TTS client to use
    ///   - onStart: Called when streaming starts
    ///   - onComplete: Called when streaming completes
    func streamSingleChunk(
        _ text: String,
        voice: String,
        instructions: String?,
        ttsClient: TTSCapable,
        onStart: (() -> Void)?,
        onComplete: @escaping (Error?) -> Void
    ) {
        // Start new streaming session
        let session = StreamingSession(id: UUID())
        currentSession = session
        
        stateManager.enterStreamSetup()
        Logger.debug("Starting single chunk stream with session: \(session.id)")
        
        // Set up streamer callbacks for this session
        setupStreamingCallbacks(for: session, onStart: onStart, onComplete: onComplete)
        
        // Send streaming request
        ttsClient.sendTTSStreamingRequest(
            text: text,
            voice: voice,
            instructions: instructions,
            onChunk: { [weak self] result in
                guard let self = self,
                      let currentSession = self.currentSession,
                      currentSession.id == session.id,
                      !currentSession.isCancelled else { return }
                
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
                guard let self = self,
                      let currentSession = self.currentSession,
                      currentSession.id == session.id else { return }
                
                if let error = error {
                    Logger.error("Streaming request error: \(error.localizedDescription)")
                    self.stateManager.exitStreamSetup()
                    self.stateManager.setBufferingState(false)
                    self.streamer.onError?(error)
                }
            }
        )
    }
    
    /// Streams multiple text chunks with seamless playback
    /// - Parameters:
    ///   - chunks: Array of text chunks to stream
    ///   - voice: The voice to use
    ///   - instructions: Optional voice instructions
    ///   - ttsClient: The TTS client to use
    ///   - onStart: Called when streaming starts
    ///   - onComplete: Called when all chunks complete
    func streamMultipleChunks(
        _ chunks: [String],
        voice: String,
        instructions: String?,
        ttsClient: TTSCapable,
        onStart: (() -> Void)?,
        onComplete: @escaping (Error?) -> Void
    ) {
        guard !chunks.isEmpty else {
            onComplete(nil)
            return
        }
        
        Logger.debug("🎵 Starting multi-chunk streaming: \(chunks.count) chunks")
        
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
                    ttsClient: ttsClient,
                    onStart: hasStarted ? nil : onStart,
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
                        
                        // Small delay for smooth transition
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
    
    /// Stops the current streaming session
    func stopStreaming() {
        // Mark current session as cancelled
        currentSession?.isCancelled = true
        currentSession = nil
        
        // Stop the streamer
        streamer.stop()
        
        Logger.debug("Streaming session stopped")
    }
    
    /// Pauses streaming playback
    /// - Returns: True if pause was successful
    @discardableResult
    func pause() -> Bool {
        return streamer.pause()
    }
    
    /// Resumes streaming playback
    /// - Returns: True if resume was successful
    @discardableResult
    func resume() -> Bool {
        return streamer.resume()
    }
    
    /// Gets the complete cached audio data
    /// - Returns: The cached audio data or nil
    func getCachedAudio() -> Data? {
        return streamer.getCachedAudio()
    }
    
    /// Saves the cached audio to a file
    /// - Parameter url: The URL to save to
    /// - Returns: True if save was successful
    func saveAudioToFile(url: URL) -> Bool {
        return streamer.saveAudioToFile(url: url)
    }
    
    // MARK: - Private Methods
    
    private func setupStreamerCallbacks() {
        streamer.onBufferingStateChanged = { [weak self] isBuffering in
            self?.stateManager.setBufferingState(isBuffering)
        }
    }
    
    private func setupStreamingCallbacks(
        for session: StreamingSession,
        onStart: (() -> Void)?,
        onComplete: @escaping (Error?) -> Void
    ) {
        streamer.onReady = { [weak self] in
            Task { @MainActor in
                guard let self = self,
                      let currentSession = self.currentSession,
                      currentSession.id == session.id else { return }
                
                self.stateManager.exitStreamSetup()
                self.stateManager.cancelTimeout()
                self.stateManager.setBufferingState(false)
                
                Logger.debug("AUDIO READY - exiting setup phase")
                self.onReady?()
                onStart?()
            }
        }
        
        streamer.onFinish = { [weak self] in
            Task { @MainActor in
                guard let self = self,
                      let currentSession = self.currentSession,
                      currentSession.id == session.id else { return }
                
                if self.stateManager.isInStreamSetup {
                    Logger.debug("Ignoring finish during buffering setup")
                    return
                }
                
                Logger.debug("Stream finished normally")
                self.stateManager.cancelTimeout()
                self.stateManager.setBufferingState(false)
                self.onFinish?()
                onComplete(nil)
            }
        }
        
        streamer.onError = { [weak self] error in
            Task { @MainActor in
                guard let self = self,
                      let currentSession = self.currentSession,
                      currentSession.id == session.id else { return }
                
                self.stateManager.exitStreamSetup()
                self.stateManager.cancelTimeout()
                self.stateManager.setBufferingState(false)
                
                Logger.error("Stream error: \(error.localizedDescription)")
                
                // Handle chunk overflow gracefully
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
    }
    
    // MARK: - Cleanup
    
    func clearCallbacks() {
        onReady = nil
        onFinish = nil
        onError = nil
        onBufferingStateChanged = nil
    }
    
    deinit {
        stopStreaming()
        clearCallbacks()
    }
}