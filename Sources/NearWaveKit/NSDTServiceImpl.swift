import Foundation

// MARK: - NSDTServiceImpl

/// Concrete implementation of `NSDTService`.
/// Wires together the encoder, decoder, and audio engine.
public final class NSDTServiceImpl: NSDTService {

    /// Callback invoked when valid data is decoded from audio.
    public var onDataReceived: (([UInt8]) -> Void)?

    private let config: NSDTConfig
    private let encoder: FSKEncoder
    private let decoder: FSKDecoder
    private let audioEngine: AudioEngineManager

    public init(config: NSDTConfig = .default) {
        self.config = config
        self.encoder = FSKEncoder(config: config)
        self.decoder = FSKDecoder(config: config)
        self.audioEngine = AudioEngineManager(config: config)

        // Wire decoder output to our public callback.
        self.decoder.onFrameDecoded = { [weak self] data in
            NWLog.debug("[NSDTService] received data (\(data.count) bytes): \(data)")
            self?.onDataReceived?(data)
        }
    }

    // MARK: - Listening

    /// Start listening for incoming ultrasonic frames via the microphone.
    public func startListening() {
        NWLog.debug("[NSDTService] startListening")
        decoder.reset()

        audioEngine.startInput { [weak self] samples in
            self?.decoder.process(samples: samples)
        }
    }

    /// Stop listening.
    public func stopListening() {
        NWLog.debug("[NSDTService] stopListening")
        audioEngine.stopInput()
        decoder.reset()
    }

    // MARK: - Sending

    /// Encode and transmit raw bytes as an ultrasonic audio signal.
    /// The frame is repeated `config.repeatCount` times for robustness.
    public func send(data: [UInt8]) {
        precondition(data.count <= 255, "Data must be at most 255 bytes per frame")

        NWLog.debug("[NSDTService] send: \(data.count) bytes → \(data)")

        let samples = encoder.encode(data: data)

        NWLog.debug("[NSDTService] playing \(samples.count) samples")
        audioEngine.play(samples: samples) {
            NWLog.debug("[NSDTService] transmission complete")
        }
    }
}
