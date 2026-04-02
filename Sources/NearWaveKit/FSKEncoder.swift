import Foundation

// MARK: - FSKEncoder

/// Encodes a Frame into FSK audio samples suitable for real-world
/// speaker → air → microphone transmission on iOS.
///
/// Pipeline:  Frame → bytes → bits → (tone + silence gap) per bit → packet gap → repeat
///
/// Each bit is represented by a fixed-duration sine tone with a short cosine
/// fade-in / fade-out to eliminate click transients that confuse iOS DSP.
/// A silence gap follows every tone, and a longer silence gap separates
/// repeated packet transmissions.
public final class FSKEncoder: Sendable {

    private let config: NSDTConfig

    public init(config: NSDTConfig = .default) {
        self.config = config
    }

    // MARK: - Public API

    /// Encode a frame into PCM Float32 audio samples, repeated `config.repeatCount` times
    /// with packet gaps between each repetition.
    public func encode(frame: Frame) -> [Float] {
        config.logSummary()

        let bytes = frame.encode()              // [Preamble][Len][Data][Checksum]
        let bits = BitConverter.bytesToBits(bytes)

        NWLog.debug("[FSKEncoder] frame bytes (\(bytes.count)): \(bytes)")
        NWLog.debug("[FSKEncoder] total bits: \(bits.count)")

        let singlePacket = generatePacket(for: bits)
        let packetGap = [Float](repeating: 0.0, count: config.samplesPerPacketGap)

        // Assemble: [packet][gap][packet][gap]...[packet]  (no trailing gap)
        var samples: [Float] = []
        let totalSize = singlePacket.count * config.repeatCount
                      + packetGap.count * max(config.repeatCount - 1, 0)
        samples.reserveCapacity(totalSize)

        for i in 0 ..< config.repeatCount {
            samples.append(contentsOf: singlePacket)
            if i < config.repeatCount - 1 {
                samples.append(contentsOf: packetGap)
            }
        }

        let durationMs = Double(samples.count) / config.sampleRate * 1000
        NWLog.debug("[FSKEncoder] total samples: \(samples.count) (\(config.repeatCount) repeats, \(String(format: "%.0f", durationMs)) ms)")
        return samples
    }

    /// Encode raw data (convenience — wraps in a Frame automatically).
    public func encode(data: [UInt8]) -> [Float] {
        let frame = Frame(data: data)
        return encode(frame: frame)
    }

    // MARK: - Internal

    /// Generate one full packet: a sequence of (tone + bit-gap) for every bit.
    private func generatePacket(for bits: [Bool]) -> [Float] {
        let samplesPerBit = config.samplesPerBit
        let samplesPerGap = config.samplesPerBitGap
        var samples: [Float] = []
        samples.reserveCapacity(bits.count * (samplesPerBit + samplesPerGap))

        // Number of samples for the cosine fade envelope on each end.
        // ~2 ms or 10% of the tone, whichever is smaller.
        let fadeLen = min(Int(config.sampleRate * 0.002), samplesPerBit / 10)

        let twoPi = 2.0 * Double.pi

        for bit in bits {
            let freq = bit ? config.effectiveFreq1 : config.effectiveFreq0

            // --- Tone with fade-in / fade-out ---
            for i in 0 ..< samplesPerBit {
                let t = Double(i) / config.sampleRate
                var value = Float(sin(twoPi * freq * t)) * config.amplitude

                // Cosine fade-in (first fadeLen samples)
                if i < fadeLen {
                    let envelope = Float(0.5 * (1.0 - cos(Double.pi * Double(i) / Double(fadeLen))))
                    value *= envelope
                }
                // Cosine fade-out (last fadeLen samples)
                else if i >= samplesPerBit - fadeLen {
                    let remaining = samplesPerBit - 1 - i
                    let envelope = Float(0.5 * (1.0 - cos(Double.pi * Double(remaining) / Double(fadeLen))))
                    value *= envelope
                }

                samples.append(value)
            }

            // --- Silence gap after the tone ---
            for _ in 0 ..< samplesPerGap {
                samples.append(0.0)
            }
        }

        return samples
    }
}
