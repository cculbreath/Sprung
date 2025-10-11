// swift-format-disable: UseExplicitSelf

//
//  TTSAudioStreamer.swift
//  Sprung
//
//  Created by Christopher Culbreath on 4/23/25.
//

import AudioToolbox // for AudioFileTypeID
import ChunkedAudioPlayer
import Foundation
import os.log // For system logging

/// Drop-in replacement for StreamingTTSPlayer that handles buffered audio playback
final class TTSAudioStreamer {
    // MARK: - Properties

    /// Audio file type hint (e.g. MP3)
    private let fileType: AudioFileTypeID = kAudioFileMP3Type

    /// Tracks total buffered data size to prevent excessive memory usage
    private var totalBufferedSize: Int = 0

    /// Maximum buffer size allowed (50MB) - increased for better caching
    private let maxBufferSize: Int = 50 * 1024 * 1024
    
    /// Cache of all received audio data for persistent playback
    private var completeAudioCache: Data = Data()

    /// Count of received chunks for monitoring
    private var chunkCount: Int = 0

    /// Maximum number of chunks to allow before forcing cleanup
    private let maxChunkCount: Int = 300

    /// Continuation for feeding audio data stream
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?

    /// Current AsyncThrowingStream instance (holds the stream for player.start)
    private var currentStream: AsyncThrowingStream<Data, Error>?

    /// Buffer of initial chunks before playback starts
    private var initialChunks: [Data]?

    /// Number of initial chunks to buffer before beginning playback
    private let initialBufferChunkCount = 2

    /// Track local paused state because AudioPlayer does not expose playback flags
    private var isPausedFlag = false

    /// Tracks if we're in the initial buffering phase
    private var isBufferingFlag = false

    /// Audio player handling buffered streaming
    private lazy var player: AudioPlayer = .init(
        didStartPlaying: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                Logger.debug("TTSAudioStreamer: didStartPlaying callback")
                self.isPausedFlag = false
                self.setBufferingState(false) // Exit buffering state when playback starts
                if let readyHandler = self.onReady {
                    readyHandler()
                }
            }
        },
        didFinishPlaying: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                Logger.debug("TTSAudioStreamer: didFinishPlaying callback")
                self.isPausedFlag = false
                self.setBufferingState(false)
                if let error = self.player.currentError {
                    Task { @MainActor in 
                        if let errorHandler = self.onError {
                            errorHandler(error)
                        }
                    }
                } else {
                    Task { @MainActor in 
                        if let finishHandler = self.onFinish {
                            finishHandler()
                        }
                    }
                }
            }
        }
    )

    // MARK: - Callbacks

    /// Called when the player is ready to start playback (buffering complete)
    var onReady: (() -> Void)?

    /// Called when playback has finished
    var onFinish: (() -> Void)?
    

    /// Called on playback or decoding error
    var onError: ((Error) -> Void)?

    /// Called when buffering state changes
    var onBufferingStateChanged: ((Bool) -> Void)?

    // MARK: - Computed Properties

    // MARK: - Initialization

    init() {
    }

    deinit {
        // Force cleanup on deinit - must dispatch to MainActor
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.stop()
            // Reset all callbacks to break potential reference cycles
            self.onReady = nil
            self.onFinish = nil
            self.onError = nil
            self.onBufferingStateChanged = nil
        }
    }

    // MARK: - Private Methods

    /// Set the buffering state and notify listeners
    private func setBufferingState(_ buffering: Bool) {
        if isBufferingFlag != buffering {
            isBufferingFlag = buffering
            Task { @MainActor in
            if let bufferingHandler = self.onBufferingStateChanged {
                bufferingHandler(buffering)
            }
            Logger.debug("TTSAudioStreamer: Buffering state changed to \(buffering)")
        }
        }
    }

    /// Reset all buffer tracking metrics
    private func resetBufferMetrics() {
        totalBufferedSize = 0
        chunkCount = 0
        // This helps in monitoring if resource cleanup is happening correctly
        Logger.debug("TTSAudioStreamer: Buffer metrics reset")
        // Note: We intentionally don't clear completeAudioCache to maintain entire audio history
    }

    // MARK: - Public Methods
    

    /// Append a new chunk of audio data for playback.
    /// On the first chunk, buffer it before starting the player to ensure initial data is available.
    func append(_ data: Data) {
        // First, add to our complete audio cache for persistent playback
        completeAudioCache.append(data)
        
        // Check buffer limits before processing new data
        totalBufferedSize += data.count
        chunkCount += 1

        // Check if we've exceeded memory limits
        if totalBufferedSize > maxBufferSize {
            Logger.error("TTSAudioStreamer: Buffer size exceeded limit (\(totalBufferedSize)/\(maxBufferSize) bytes). Stopping playback.")
            let error = NSError(
                domain: "TTSAudioStreamer",
                code: 1001,
                userInfo: [
                    NSLocalizedDescriptionKey: "Buffer size limit exceeded",
                ]
            )

            // Must dispatch to MainActor for stop() call
            Task { @MainActor in
                self.stop()
                self.onError?(error)
            }
            return
        }

        // Check if we've received too many chunks - but allow audio to continue playing
        if chunkCount > maxChunkCount {
            Logger.warning("TTSAudioStreamer: Many chunks accumulated (\(chunkCount)/\(maxChunkCount)). Forcing stream completion to prevent overflow.")
            
            // Report overflow condition but CONTINUE playback of existing audio
            // Create a specific overflow error that can be handled specially
            let overflowError = NSError(
                domain: "TTSAudioStreamer",
                code: 1002,
                userInfo: [
                    NSLocalizedDescriptionKey: "Chunk limit exceeded, but continuing playback",
                ]
            )
            
            Task { @MainActor in
                // Call onError with the special error code that won't stop playback
                self.onError?(overflowError)
                
                // Reset buffer metrics but DON'T stop the stream
                self.resetBufferMetrics()
            }
            return
        }

        // New streaming session: buffer initial chunks up to threshold
        if continuation == nil {
            // First chunk: create stream and start buffering
            initialChunks = [data]

            // Signal that we're buffering
            setBufferingState(true)
            // Log initial chunk receipt
            let dataSize = data.count
            Logger.debug("TTSAudioStreamer: Starting to buffer first chunk, size: \(dataSize)")

            // Create the async stream and capture its continuation
            let stream = AsyncThrowingStream<Data, Error> { cont in
                self.continuation = cont
                cont.onTermination = { @Sendable [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        Logger.debug("TTSAudioStreamer: Stream terminated, cleaning up resources")
                        self.continuation = nil
                        self.currentStream = nil
                        self.initialChunks = nil
                        self.setBufferingState(false)
                        self.resetBufferMetrics()
                    }
                }
            }
            currentStream = stream
        }
        // If still buffering initial chunks, accumulate until threshold reached
        else if var currentInitialChunks = initialChunks {
            currentInitialChunks.append(data)
            initialChunks = currentInitialChunks
            Logger.debug("TTSAudioStreamer: Added chunk to buffer, now have \(currentInitialChunks.count)/\(initialBufferChunkCount), total size: \(totalBufferedSize)")

            if currentInitialChunks.count >= initialBufferChunkCount {
                // Ready to start playback with buffered data
                guard let cont = continuation, let stream = currentStream else {
                    return
                }
                let buffered = currentInitialChunks
                initialChunks = nil

                // Signal that we're done buffering
                Logger.debug("TTSAudioStreamer: Buffer threshold reached, starting playback")

                Task { @MainActor in
                    // Yield buffered chunks first
                    for chunk in buffered {
                        cont.yield(chunk)
                    }
                    // Now start playback
                    self.player.start(stream, type: self.fileType)

                    // We'll let onReady do the transition out of buffering state
                    // This ensures we don't briefly exit buffering state before
                    // the audio is actually ready to play
                }
            }
        }
        // Already started, yield chunks immediately
        else {
            guard let cont = continuation else { 
                Logger.warning("TTSAudioStreamer: Tried to append chunk but no continuation available")
                return 
            }
            Logger.debug("TTSAudioStreamer: Yielding chunk directly to player, size: \(data.count), total: \(totalBufferedSize)")
            Task { @MainActor in
                cont.yield(data)
            }
        }
    }

    /// Stop playback and clear buffered data
    func stop() {
        Task { @MainActor in
            Logger.debug("TTSAudioStreamer: Stopping playback, cleaning up resources")

            // Immediately finish and clear continuation
            if let cont = continuation {
                cont.finish()
                continuation = nil
            }

            // Clear active streaming buffers but preserve complete audio cache
            currentStream = nil
            initialChunks = nil
            isPausedFlag = false
            resetBufferMetrics() // This will reset counters but not clear completeAudioCache

            // Make absolutely sure buffering state is cleared
            if isBufferingFlag {
                Logger.debug("TTSAudioStreamer: Forcing buffering state to false on stop")
                setBufferingState(false)
            }

            player.stop()
            Task { @MainActor in 
                if let finishHandler = self.onFinish {
                    finishHandler()
                }
            }
        }
    }

    // MARK: - Transport Controls

    /// Pause playback without dropping buffered data.
    /// - Returns: `true` if a pause actually occurred.
    @discardableResult
    func pause() -> Bool {
        guard isPausedFlag == false else { return false }
        Logger.debug("TTSAudioStreamer: Pausing playback")
        player.pause() // AudioPlayer supports pause()
        isPausedFlag = true

        // Make sure buffering is off during pause
        if isBufferingFlag {
            Logger.debug("TTSAudioStreamer: Forcing buffering state to false on pause")
            setBufferingState(false)
        }
        return true
    }

    /// Resume playback if previously paused.
    /// - Returns: `true` if a resume actually occurred.
    @discardableResult
    func resume() -> Bool {
        guard isPausedFlag else { return false }
        Logger.debug("TTSAudioStreamer: Resuming playback")
        player.resume() // resumes from pause
        isPausedFlag = false

        // Make sure buffering is off during resume
        if isBufferingFlag {
            Logger.debug("TTSAudioStreamer: Forcing buffering state to false on resume")
            setBufferingState(false)
        }
        return true
    }

    // MARK: - Debug

}

// swift-format-enable: all
