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

    /// Configure the shared audio session for recording + playback.
    /// Must be called before accessing `inputNode.inputFormat(forBus:)`,
    /// otherwise iOS returns a zero-rate / zero-channel format and the tap crashes.
    private func configureAudioSession() {
        #if os(iOS) || os(tvOS) || os(watchOS)
        let session = AVAudioSession.sharedInstance()
        do {
            // .measurement disables iOS AGC, noise suppression, and automatic
            // gain adjustments — critical for reliable FSK tone detection.
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker, .mixWithOthers, .allowBluetoothA2DP]
            )
            try session.setPreferredSampleRate(config.sampleRate)
            // Request a small IO buffer for lower latency (not critical, but helps).
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
            NWLog.debug("[AudioEngine] audio session activated — mode: measurement")
            NWLog.debug("[AudioEngine]   hw sampleRate = \(session.sampleRate)")
            NWLog.debug("[AudioEngine]   hw ioBufferDuration = \(session.ioBufferDuration)")
        } catch {
            NWLog.debug("[AudioEngine] failed to configure audio session: \(error)")
        }
        #else
        NWLog.debug("[AudioEngine] audio session configuration skipped (macOS)")
        #endif
    }

    /// Start capturing microphone audio.
    /// `callback` is invoked on an internal audio thread with chunks of Float32 samples.
    public func startInput(callback: @escaping ([Float]) -> Void) {
        guard !isInputRunning else {
            NWLog.debug("[AudioEngine] input already running")
            return
        }

        // Activate the audio session BEFORE touching inputNode so the
        // hardware format reports valid sample-rate and channel count.
        configureAudioSession()

        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        let desiredSampleRate = config.sampleRate

        NWLog.debug("[AudioEngine] hardware input format: \(hardwareFormat)")

        // Guard against a still-invalid hardware format (e.g. 0 Hz).
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            NWLog.debug("[AudioEngine] hardware format is invalid — cannot install tap")
            return
        }

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

        // On iOS the tap format MUST match the hardware input format,
        // otherwise installTap crashes with a format-mismatch error.
        // We tap using the hardware format and convert ourselves.
        let needsConversion = (hardwareFormat.sampleRate != desiredSampleRate
                               || hardwareFormat.channelCount != 1)

        let converter: AVAudioConverter?
        if needsConversion {
            converter = AVAudioConverter(from: hardwareFormat, to: desiredFormat)
            if converter == nil {
                NWLog.debug("[AudioEngine] failed to create audio converter")
            }
        } else {
            converter = nil
        }

        // Tap with the hardware format so there is no mismatch.
        let bufferSize: AVAudioFrameCount = 1024
        let tapFormat = needsConversion ? hardwareFormat : desiredFormat

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: tapFormat) { buffer, _ in
            if let converter = converter {
                // Convert hardware buffer → desired mono / sample-rate buffer.
                let ratio = desiredSampleRate / hardwareFormat.sampleRate
                let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
                guard let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: desiredFormat,
                    frameCapacity: capacity
                ) else { return }

                var error: NSError?
                var consumed = false
                converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                    if consumed {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    consumed = true
                    outStatus.pointee = .haveData
                    return buffer
                }

                if let error = error {
                    NWLog.debug("[AudioEngine] conversion error: \(error)")
                    return
                }

                guard let channelData = convertedBuffer.floatChannelData else { return }
                let frameCount = Int(convertedBuffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
                callback(samples)
            } else {
                // No conversion needed — formats already match.
                guard let channelData = buffer.floatChannelData else { return }
                let frameCount = Int(buffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
                callback(samples)
            }
        }

        do {
            engine.prepare()
            try engine.start()
            isInputRunning = true
            NWLog.debug("[AudioEngine] input started (sampleRate=\(desiredSampleRate))")
        } catch {
