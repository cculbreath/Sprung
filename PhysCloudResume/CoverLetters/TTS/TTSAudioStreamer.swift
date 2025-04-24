//
//  TTSAudioStreamer.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/23/25.
//

import AudioToolbox // for AudioFileTypeID
import ChunkedAudioPlayer
import Foundation

/// Drop-in replacement for StreamingTTSPlayer
@MainActor
final class TTSAudioStreamer {
    // MARK: - Properties
    
    /// Audio file type hint (e.g. MP3)
    private let fileType: AudioFileTypeID = kAudioFileMP3Type
    
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
                self?.isPausedFlag = false
                self?.onReady?()
            }
        },
        didFinishPlaying: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isPausedFlag = false
                if let error = self.player.currentError {
                    Task { @MainActor in self.onError?(error) }
                } else {
                    Task { @MainActor in self.onFinish?() }
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
    
    /// Returns the current buffering state
    var isBuffering: Bool {
        return isBufferingFlag
    }
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Private Methods
    
    /// Set the buffering state and notify listeners
    private func setBufferingState(_ buffering: Bool) {
        if isBufferingFlag != buffering {
            isBufferingFlag = buffering
            Task { @MainActor in
                self.onBufferingStateChanged?(buffering)
                print("TTSAudioStreamer: Buffering state changed to \(buffering)")
            }
        }
    }

    // MARK: - Public Methods
    
    /// Append a new chunk of audio data for playback.
    /// On the first chunk, buffer it before starting the player to ensure initial data is available.
    func append(_ data: Data) {
        // New streaming session: buffer initial chunks up to threshold
        if continuation == nil {
            // First chunk: create stream and start buffering
            initialChunks = [data]
            
            // Signal that we're buffering
            setBufferingState(true)
            
            // Create the async stream and capture its continuation
            let stream = AsyncThrowingStream<Data, Error> { cont in
                self.continuation = cont
                cont.onTermination = { @Sendable _ in
                    Task { @MainActor [weak self] in
                        self?.continuation = nil
                        self?.currentStream = nil
                        self?.initialChunks = nil
                        self?.setBufferingState(false)
                    }
                }
            }
            currentStream = stream
        }
        // If still buffering initial chunks, accumulate until threshold reached
        else if let chunks = initialChunks {
            initialChunks!.append(data)
            if initialChunks!.count >= initialBufferChunkCount {
                // Ready to start playback with buffered data
                guard let cont = continuation, let stream = currentStream else { return }
                let buffered = initialChunks!
                initialChunks = nil
                
                // Signal that we're done buffering
                setBufferingState(false)
                
                Task { @MainActor in
                    // Yield buffered chunks first
                    for chunk in buffered {
                        cont.yield(chunk)
                    }
                    // Now start playback
                    self.player.start(stream, type: self.fileType)
                }
            }
        }
        // Already started, yield chunks immediately
        else {
            guard let cont = continuation else { return }
            Task { @MainActor in
                cont.yield(data)
            }
        }
    }

    /// Stop playback and clear buffered data
    func stop() {
        Task { @MainActor in
            continuation?.finish()
            continuation = nil
            isPausedFlag = false
            setBufferingState(false)
            player.stop()
            Task { @MainActor in self.onFinish?() }
        }
    }

    // MARK: - Transport Controls
    
    /// Pause playback without dropping buffered data.
    /// - Returns: `true` if a pause actually occurred.
    @discardableResult
    func pause() -> Bool {
        guard isPausedFlag == false else { return false }
        player.pause() // AudioPlayer supports pause()
        isPausedFlag = true
        return true
    }

    /// Resume playback if previously paused.
    /// - Returns: `true` if a resume actually occurred.
    @discardableResult
    func resume() -> Bool {
        guard isPausedFlag else { return false }
        player.resume() // resumes from pause
        isPausedFlag = false
        return true
    }
}