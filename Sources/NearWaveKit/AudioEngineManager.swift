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

    /// Enable to print verbose mic-level debug logs (🎤 lines).
    /// Set to `false` once you've confirmed input works.
    public var isDebugLoggingEnabled = true

    /// Counter used to throttle debug prints (every Nth buffer).
    private var tapCallbackCount: Int = 0

    public init(config: NSDTConfig = .default) {
        self.config = config
    }

    // MARK: - Audio Session (iOS only)

    /// Configure the shared audio session for recording + playback.
    /// Must be called before accessing `inputNode.inputFormat(forBus:)`,
    /// otherwise iOS returns a zero-rate / zero-channel format and the tap crashes.
    private func configureAudioSession() {
        #if os(iOS) || os(tvOS) || os(watchOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker, .mixWithOthers, .allowBluetoothA2DP]
            )
            try session.setPreferredSampleRate(config.sampleRate)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)

            if isDebugLoggingEnabled {
                print("🎤 Audio session activated")
                print("🎤   category      = \(session.category.rawValue)")
                print("🎤   sampleRate    = \(session.sampleRate)")
                print("🎤   inputChannels = \(session.inputNumberOfChannels)")
                print("🎤   outputChannels= \(session.outputNumberOfChannels)")
            }
            NWLog.debug("[AudioEngine] audio session activated (hw sampleRate=\(session.sampleRate))")
        } catch {
            print("🎤 ❌ Audio session configuration FAILED: \(error)")
            NWLog.debug("[AudioEngine] failed to configure audio session: \(error)")
        }
        #else
        NWLog.debug("[AudioEngine] audio session configuration skipped (macOS)")
        #endif
    }

    /// Request microphone permission and log the result.
    /// Call before `startInput` to ensure the user has granted access.
    private func requestMicPermission(completion: @escaping (Bool) -> Void) {
        #if os(iOS) || os(tvOS)
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if granted {
                print("🎤 ✅ Microphone permission GRANTED")
            } else {
                print("🎤 ❌ Microphone permission DENIED")
            }
            completion(granted)
        }
        #else
        // macOS does not use AVAudioSession — permission is handled differently.
        NWLog.debug("[AudioEngine] mic permission check skipped (macOS)")
        completion(true)
        #endif
    }

    // MARK: - Input (Microphone)

    /// Start capturing microphone audio.
    /// `callback` is invoked on an internal audio thread with chunks of Float32 samples.
    public func startInput(callback: @escaping ([Float]) -> Void) {
        guard !isInputRunning else {
            NWLog.debug("[AudioEngine] input already running")
            return
        }

        // Step 1 — Ensure microphone permission
        requestMicPermission { [weak self] granted in
            guard granted else {
                print("🎤 ❌ Cannot start input — mic permission denied")
                return
            }
            DispatchQueue.main.async {
                self?.startInputAfterPermission(callback: callback)
            }
        }
    }

    private func startInputAfterPermission(callback: @escaping ([Float]) -> Void) {
        guard !isInputRunning else { return }

        // Step 2 — Activate the audio session BEFORE touching inputNode
        configureAudioSession()

        let inputNode = engine.inputNode

        // Use outputFormat — this is what the input node *delivers* to the engine,
        // and is always valid after the session is active.
        // (inputFormat can return 0 Hz / 0 ch on iOS.)
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        let desiredSampleRate = config.sampleRate

        if isDebugLoggingEnabled {
            print("🎤 inputNode.outputFormat = \(hardwareFormat)")
            print("🎤   sampleRate   = \(hardwareFormat.sampleRate)")
            print("🎤   channelCount = \(hardwareFormat.channelCount)")
            print("🎤   desired SR   = \(desiredSampleRate)")
        }
        NWLog.debug("[AudioEngine] hardware input format: \(hardwareFormat)")

        // Guard against a still-invalid hardware format (e.g. 0 Hz).
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            print("🎤 ❌ Hardware format is INVALID (0 Hz or 0 ch) — cannot install tap")
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
            print("🎤 ❌ Failed to create desired AVAudioFormat")
            NWLog.debug("[AudioEngine] failed to create desired audio format")
            return
        }

        // On iOS the tap format MUST match the hardware output format,
        // otherwise installTap crashes with a format-mismatch error.
        let needsConversion = (hardwareFormat.sampleRate != desiredSampleRate
                               || hardwareFormat.channelCount != 1)

        let converter: AVAudioConverter?
        if needsConversion {
            converter = AVAudioConverter(from: hardwareFormat, to: desiredFormat)
            if converter == nil {
                print("🎤 ⚠️ Failed to create AVAudioConverter")
                NWLog.debug("[AudioEngine] failed to create audio converter")
            } else if isDebugLoggingEnabled {
                print("🎤 Converter created: \(hardwareFormat.sampleRate)Hz \(hardwareFormat.channelCount)ch → \(desiredSampleRate)Hz 1ch")
            }
        } else {
            converter = nil
            if isDebugLoggingEnabled {
                print("🎤 No conversion needed — formats already match")
            }
        }

        // Step 3 — Install tap with the hardware format so there is no mismatch.
        let bufferSize: AVAudioFrameCount = 2048
        let tapFormat = needsConversion ? hardwareFormat : desiredFormat

        if isDebugLoggingEnabled {
            print("🎤 Installing tap: bus=0, bufferSize=\(bufferSize), format=\(tapFormat)")
        }

        tapCallbackCount = 0

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: tapFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.tapCallbackCount += 1

            // --- Extract samples (with optional conversion) ---
            let samples: [Float]

            if let converter = converter {
                let ratio = desiredSampleRate / hardwareFormat.sampleRate
                let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
                guard let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: desiredFormat,
                    frameCapacity: capacity
                ) else {
                    if self.isDebugLoggingEnabled { print("🎤 ❌ Failed to allocate conversion buffer") }
                    return
                }

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
                    if self.isDebugLoggingEnabled { print("🎤 ❌ Conversion error: \(error)") }
                    NWLog.debug("[AudioEngine] conversion error: \(error)")
                    return
                }

                guard let channelData = convertedBuffer.floatChannelData else {
                    if self.isDebugLoggingEnabled { print("🎤 ❌ convertedBuffer.floatChannelData is nil") }
                    return
                }
                let frameCount = Int(convertedBuffer.frameLength)
                if frameCount == 0 {
                    if self.isDebugLoggingEnabled { print("🎤 ⚠️ Converted buffer has 0 frames") }
                    return
                }
                samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
            } else {
                // No conversion needed
                guard let channelData = buffer.floatChannelData else {
                    if self.isDebugLoggingEnabled { print("🎤 ❌ buffer.floatChannelData is nil") }
                    return
                }
                let frameCount = Int(buffer.frameLength)
                if frameCount == 0 {
                    if self.isDebugLoggingEnabled { print("🎤 ⚠️ Buffer has 0 frames") }
                    return
                }
                samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
            }

            // --- Debug logging (every 50th buffer to avoid spam) ---
            if self.isDebugLoggingEnabled && self.tapCallbackCount % 50 == 1 {
                var maxAmp: Float = 0
                var energy: Float = 0
                for s in samples {
                    let a = abs(s)
                    if a > maxAmp { maxAmp = a }
                    energy += a
                }
                print("🎤 Tap #\(self.tapCallbackCount): \(samples.count) samples | maxAmp=\(String(format: "%.6f", maxAmp)) | energy=\(String(format: "%.2f", energy))")
            }

            // Step 4 — Deliver to decoder
            callback(samples)
        }

        // Step 5 — Start engine
        do {
            engine.prepare()
            try engine.start()
            isInputRunning = true

            let running = engine.isRunning
            if isDebugLoggingEnabled {
                print("🎤 ✅ Audio engine started — isRunning=\(running)")
            }
            NWLog.debug("[AudioEngine] input started (sampleRate=\(desiredSampleRate), isRunning=\(running))")
        } catch {
            print("🎤 ❌ Engine start FAILED: \(error)")
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
        configureAudioSession()
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
