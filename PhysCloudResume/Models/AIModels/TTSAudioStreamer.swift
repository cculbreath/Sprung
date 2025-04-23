import AudioToolbox // for AudioFileTypeID
import ChunkedAudioPlayer
import Foundation

/// Drop-in replacement for StreamingTTSPlayer
@MainActor
final class TTSAudioStreamer {
    /// Audio file type hint (e.g. MP3)
    private let fileType: AudioFileTypeID = kAudioFileMP3Type
    /// Continuation for feeding audio data stream
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?
    /// Track local paused state because AudioPlayer does not expose playback flags
    private var isPausedFlag = false
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

    /// Called when the player is ready to start playback (buffering complete)
    var onReady: (() -> Void)?
    /// Called when playback has finished
    var onFinish: (() -> Void)?
    /// Called on playback or decoding error
    var onError: ((Error) -> Void)?

    init() {}

    /// Append a new chunk of audio data for playback
    func append(_ data: Data) {
        if continuation == nil {
            let stream = AsyncThrowingStream<Data, Error> { cont in
                self.continuation = cont
                cont.onTermination = { @Sendable _ in
                    Task { @MainActor [weak self] in
                        self?.continuation = nil
                    }
                }
            }
            player.start(stream, type: fileType)
        }
        Task { @MainActor in self.continuation?.yield(data) }
    }

    /// Stop playback and clear buffered data
    func stop() {
        Task { @MainActor in
            continuation?.finish()
            continuation = nil
            isPausedFlag = false
            player.stop()
            Task { @MainActor in self.onFinish?() }
        }
    }

    // MARK: - External transport controls (pause / resume)

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
