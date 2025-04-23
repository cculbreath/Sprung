//  StreamingTTSPlayer.swift
//  PhysCloudResume
//
//  Created by OpenAI Codex CLI on 2025‑04‑22.
//
//  This class provides extremely lightweight, *play‑while‑downloading* support
//  for the MP3 fragments returned by OpenAI’s TTS **streaming** endpoint.
//
//  Key points:
//  • AudioFileStream parses the incoming MP3 bytes and tells us the encoded
//    format plus packet boundaries.
//  • AVAudioConverter decodes each packet batch to 32‑bit float PCM.
//  • AVAudioEngine + AVAudioPlayerNode handle real‑time playback; we simply
//    enqueue freshly‑decoded `AVAudioPCMBuffer`s as they become available.
//  • Everything Core Audio related lives on a dedicated serial Dispatch queue
//    to keep thread‑safety worries at bay.
//
//  The implementation purposefully skips a lot of edge‑case handling (seeking,
//  sample‑rate conversion, underflow recovery, etc.) because TTS clips are
//  short and come from a trustworthy source (OpenAI).  It is *good enough* for
//  the instant‑feedback UX we want.

import AudioToolbox
import AVFoundation
import Foundation

/// Simple progressive MP3 player built on `AVAudioEngine` + `AVAudioConverter`.
final class StreamingTTSPlayer {
    // MARK: – Public surface

    /// Append the next chunk of MP3 data. Safe to call from any thread.
    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        workQueue.async { [self] in
            parse(mp3Data: data)
        }
    }

    /// Stop playback and release resources. Synchronous.
    func stop() {
        workQueue.sync { [self] in
            teardownEngine()
            teardownFileStream()
        }
    }

    deinit {
        stop()
    }

    // MARK: – Private

    // Dedicated serial queue for **all** Core Audio interaction.
    fileprivate let workQueue = DispatchQueue(label: "com.physresume.ttsStreamingEngine")

    // The incremental parser for MP3 byte streams.
    private var audioFileStream: AudioFileStreamID?

    // Once the stream format becomes known we set these up.
    private var inputFormat: AVAudioFormat?
    private var outputFormat: AVAudioFormat?
    private var converter: AVAudioConverter?

    // Playback chain.
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var engineRunning = false

    // Helper pointer for callback bridging.
    private var selfPointer: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }

    // MARK: – Init

    init() {
        let status = AudioFileStreamOpen(selfPointer,
                                         afs_PropertyListener,
                                         afs_PacketsListener,
                                         kAudioFileMP3Type,
                                         &audioFileStream)
        if status != noErr {
            print("[StreamingTTSPlayer] AudioFileStreamOpen error: \(status)")
        }
    }

    // MARK: – Parsing helpers

    private func parse(mp3Data: Data) {
        guard let stream = audioFileStream else { return }
        mp3Data.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return }
            let status = AudioFileStreamParseBytes(stream,
                                                   UInt32(mp3Data.count),
                                                   base,
                                                   [])
            if status != noErr {
                print("[StreamingTTSPlayer] AudioFileStreamParseBytes error: \(status)")
            }
        }
    }

    fileprivate func handle(property id: AudioFileStreamPropertyID) {
        guard let stream = audioFileStream else { return }

        switch id {
        case kAudioFileStreamProperty_DataFormat:
            var asbd = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout.size(ofValue: asbd))
            let status = AudioFileStreamGetProperty(stream, id, &size, &asbd)
            guard status == noErr else { return }

            inputFormat = AVAudioFormat(streamDescription: &asbd)
            guard let inputFormat = inputFormat else { return }

            // We’ll use N‑channel 32‑bit float PCM at the same sample rate.
            outputFormat = AVAudioFormat(standardFormatWithSampleRate: Double(asbd.mSampleRate), channels: inputFormat.channelCount)

            if let outputFormat = outputFormat {
                converter = AVAudioConverter(from: inputFormat, to: outputFormat)
            }

            setupEngineIfNeeded()

        default:
            break
        }
    }

    fileprivate func handle(packetBytes: UInt32,
                            packetCount: UInt32,
                            inputData: UnsafeRawPointer,
                            packetDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?)
    {
        guard let inputFormat = inputFormat,
              let outputFormat = outputFormat,
              let converter = converter else { return }

        guard packetCount > 0 else { return }

        // Wrap compressed packets in AVAudioCompressedBuffer so AVAudioConverter can decode.
        let compressedBuffer = AVAudioCompressedBuffer(
            format: inputFormat,
            packetCapacity: AVAudioPacketCount(packetCount),
            maximumPacketSize: Int(packetBytes / packetCount)
        )

        // Copy packet descriptions (if any) into the compressed buffer.
        if let desc = packetDescriptions {
            let dstDesc = compressedBuffer.packetDescriptions!
            dstDesc.update(from: desc, count: Int(packetCount))
        }

        // Copy raw mp3 bytes.
        compressedBuffer.byteLength = packetBytes
        memcpy(compressedBuffer.data, inputData, Int(packetBytes))

        compressedBuffer.packetCount = AVAudioPacketCount(packetCount)

        // Prepare PCM buffer large enough to hold decoded audio.  We make a
        // generous estimate – converter will tell us exactly how many frames
        // it produced.
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 8192) else { return }

        var error: NSError?
        let status = converter.convert(to: pcmBuffer, error: &error) { _, outStatus -> AVAudioBuffer? in
            // Provide data on first invocation, then signal EOF.
            outStatus.pointee = .haveData
            return compressedBuffer
        }

        if status == .error {
            if let error = error { print("[StreamingTTSPlayer] AVAudioConverter error: \(error)") }
            return
        }

        guard pcmBuffer.frameLength > 0 else { return }

        // Start engine if not already running.
        if !engineRunning {
            startEngine()
        }

        // Enqueue decoded PCM to the player node.
        playerNode.scheduleBuffer(pcmBuffer, completionHandler: nil)
    }

    // MARK: – Engine management

    private func setupEngineIfNeeded() {
        guard !engineRunning else { return }

        engine.attach(playerNode)
        if let outputFormat = outputFormat {
            engine.connect(playerNode, to: engine.mainMixerNode, format: outputFormat)
        } else {
            engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
        }
    }

    private func startEngine() {
        guard !engineRunning else { return }
        do {
            try engine.start()
            playerNode.play()
            engineRunning = true
        } catch {
            print("[StreamingTTSPlayer] Failed to start AVAudioEngine: \(error)")
        }
    }

    private func teardownEngine() {
        if engineRunning {
            playerNode.stop()
            engine.stop()
            engine.reset()
            engineRunning = false
        }
    }

    private func teardownFileStream() {
        if let stream = audioFileStream {
            AudioFileStreamClose(stream)
            audioFileStream = nil
        }
    }
}

// MARK: – C callback bridges

private func afs_PropertyListener(inClientData: UnsafeMutableRawPointer,
                                  inAudioFileStream _: AudioFileStreamID,
                                  inPropertyID: AudioFileStreamPropertyID,
                                  ioFlags _: UnsafeMutablePointer<AudioFileStreamPropertyFlags>)
{
    let player = Unmanaged<StreamingTTSPlayer>.fromOpaque(inClientData).takeUnretainedValue()
    player.workQueue.async {
        player.handle(property: inPropertyID)
    }
}

private func afs_PacketsListener(inClientData: UnsafeMutableRawPointer,
                                 inNumberBytes: UInt32,
                                 inNumberPackets: UInt32,
                                 inInputData: UnsafeRawPointer,
                                 inPacketDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?)
{
    let player = Unmanaged<StreamingTTSPlayer>.fromOpaque(inClientData).takeUnretainedValue()
    player.workQueue.async {
        player.handle(packetBytes: inNumberBytes,
                      packetCount: inNumberPackets,
                      inputData: inInputData,
                      packetDescriptions: inPacketDescriptions)
    }
}
