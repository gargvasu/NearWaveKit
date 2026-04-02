@preconcurrency import AVFoundation
import Foundation

// MARK: - AudioEngineManager

/// Manages AVAudioEngine for microphone input and speaker output.
///
/// - `startInput(callback:)` installs a tap on the mic and delivers Float32 samples.
/// - `stopInput()` removes the tap and stops the engine.
/// - `play(samples:)` plays a buffer of Float32 samples through the speaker.
public final class AudioEngineManager {

    private let engine = AVAudioEngine()
    private let config: NSDTConfig

    /// Playback player node.
    private let playerNode = AVAudioPlayerNode()

    /// Whether the input tap is currently running.
    private var isInputRunning = false

    /// Whether the player node has been attached to the engine.
    private var playerAttached = false

    public init(config: NSDTConfig = .default) {
        self.config = config
    }

    // MARK: - Input (Microphone)

    /// Start capturing microphone audio.
    /// `callback` is invoked on an internal audio thread with chunks of Float32 samples.
    public func startInput(callback: @escaping ([Float]) -> Void) {
        guard !isInputRunning else {
            NWLog.debug("[AudioEngine] input already running")
            return
        }

        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        let desiredSampleRate = config.sampleRate

        NWLog.debug("[AudioEngine] hardware input format: \(hardwareFormat)")

        // We want mono Float32 at our desired sample rate.
        guard let desiredFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: desiredSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            NWLog.debug("[AudioEngine] failed to create desired audio format")
            return
        }

        // Install tap — the system will convert the hardware format for us if needed.
        // Buffer size of 1024 gives a good balance of latency vs. overhead.
        let bufferSize: AVAudioFrameCount = 1024

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: desiredFormat) { buffer, _ in
            guard let channelData = buffer.floatChannelData else { return }
            let frameCount = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
            callback(samples)
        }

        do {
            engine.prepare()
            try engine.start()
            isInputRunning = true
            NWLog.debug("[AudioEngine] input started (sampleRate=\(desiredSampleRate))")
        } catch {
            NWLog.debug("[AudioEngine] failed to start engine: \(error)")
            inputNode.removeTap(onBus: 0)
        }
    }

    /// Stop microphone capture.
    public func stopInput() {
        guard isInputRunning else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isInputRunning = false
        NWLog.debug("[AudioEngine] input stopped")
    }

    // MARK: - Output (Speaker)

    /// Play an array of Float32 mono samples through the speaker.
    /// Blocks the caller until playback is scheduled (not until it finishes).
    public func play(samples: [Float], completion: (() -> Void)? = nil) {
        let sampleRate = config.sampleRate

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            NWLog.debug("[AudioEngine] failed to create playback format")
            return
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            NWLog.debug("[AudioEngine] failed to create PCM buffer")
            return
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)

        // Copy samples into the buffer
        if let channelData = buffer.floatChannelData {
            samples.withUnsafeBufferPointer { src in
                channelData[0].initialize(from: src.baseAddress!, count: samples.count)
            }
        }

        // Attach player if needed
        if !playerAttached {
            engine.attach(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: format)
            playerAttached = true
        }

        // Stop input tap temporarily if running, because we need to reconfigure.
        let wasInputRunning = isInputRunning
        if wasInputRunning {
            // We can play while input is running if the engine is already started.
            // Only restart if the engine is not running.
        }

        if !engine.isRunning {
            engine.prepare()
            do {
                try engine.start()
            } catch {
                NWLog.debug("[AudioEngine] failed to start engine for playback: \(error)")
                return
            }
        }

        NWLog.debug("[AudioEngine] scheduling playback: \(samples.count) samples")

        playerNode.stop()
        playerNode.scheduleBuffer(buffer, at: nil, options: []) {
            NWLog.debug("[AudioEngine] playback finished")
            completion?()
        }
        playerNode.play()
    }
}
