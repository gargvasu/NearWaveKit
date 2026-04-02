import Foundation

// MARK: - FSKEncoder

/// Encodes a Frame into FSK audio samples.
///
/// Pipeline:  Frame → bytes → bits → sine-wave samples ([Float])
///
/// Each bit is represented by a fixed-duration sine tone:
///   - `0` → config.freq0
///   - `1` → config.freq1
public final class FSKEncoder: Sendable {

    private let config: NSDTConfig

    public init(config: NSDTConfig = .default) {
        self.config = config
    }

    // MARK: - Public API

    /// Encode a frame into PCM Float32 audio samples, repeated `config.repeatCount` times.
    public func encode(frame: Frame) -> [Float] {
        let bytes = frame.encode()              // [Preamble][Len][Data][Checksum]
        let bits = BitConverter.bytesToBits(bytes)

        NWLog.debug("[FSKEncoder] frame bytes (\(bytes.count)): \(bytes)")
        NWLog.debug("[FSKEncoder] total bits: \(bits.count)")

        let singlePass = generateSamples(for: bits)

        // Repeat the transmission for robustness
        var samples: [Float] = []
        samples.reserveCapacity(singlePass.count * config.repeatCount)
        for _ in 0 ..< config.repeatCount {
            samples.append(contentsOf: singlePass)
        }

        NWLog.debug("[FSKEncoder] total samples: \(samples.count) (\(config.repeatCount) repeats)")
        return samples
    }

    /// Encode raw data (convenience — wraps in a Frame automatically).
    public func encode(data: [UInt8]) -> [Float] {
        let frame = Frame(data: data)
        return encode(frame: frame)
    }

    // MARK: - Internal

    /// Generate sine-wave samples for an array of bits.
    private func generateSamples(for bits: [Bool]) -> [Float] {
        let samplesPerBit = config.samplesPerBit
        var samples: [Float] = []
        samples.reserveCapacity(bits.count * samplesPerBit)

        let twoPi = 2.0 * Double.pi

        for bit in bits {
            let freq = bit ? config.freq1 : config.freq0
            for i in 0 ..< samplesPerBit {
                let t = Double(i) / config.sampleRate
                let value = Float(sin(twoPi * freq * t)) * config.amplitude
                samples.append(value)
            }
        }

        return samples
    }
}
