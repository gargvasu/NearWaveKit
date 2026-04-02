import Foundation

// MARK: - FSKDecoder

/// Decodes FSK audio samples back into Frames.
///
/// Pipeline:  [Float] samples → frequency detection → bits → bytes → Frame
///
/// Uses the Goertzel algorithm to measure energy at freq0 and freq1 for each
/// bit-window of samples, then reconstructs bytes and validates the checksum.
public final class FSKDecoder {

    public var onFrameDecoded: ((_ data: [UInt8]) -> Void)?

    private let config: NSDTConfig

    /// Rolling sample buffer fed from the microphone.
    private var sampleBuffer: [Float] = []

    /// Expected preamble bit pattern (0xAA 0xAA → 1010101010101010).
    private let preambleBits: [Bool]

    public init(config: NSDTConfig = .default) {
        self.config = config
        self.preambleBits = BitConverter.bytesToBits(Frame.preamble)
    }

    // MARK: - Public API

    /// Feed new audio samples into the decoder. Frames are emitted via `onFrameDecoded`.
    public func process(samples: [Float]) {
        sampleBuffer.append(contentsOf: samples)
        attemptDecode()
    }

    /// Clear internal buffers (e.g. when stopping).
    public func reset() {
        sampleBuffer.removeAll()
    }

    // MARK: - Decode Pipeline

    private func attemptDecode() {
        let samplesPerBit = config.samplesPerBit

        // We need at least enough samples for the preamble to even start looking.
        let preambleSamples = preambleBits.count * samplesPerBit
        guard sampleBuffer.count >= preambleSamples else { return }

        // Step 1 — slide through buffer looking for the preamble
        if let preambleOffset = findPreamble() {
            NWLog.debug("[FSKDecoder] preamble found at sample offset \(preambleOffset)")

            // Start of payload (after preamble)
            let payloadStart = preambleOffset + preambleSamples

            // We need at least 1 byte (length) to continue → 8 bits
            let lengthBitsCount = 8
            let minSamplesForLength = payloadStart + lengthBitsCount * samplesPerBit
            guard sampleBuffer.count >= minSamplesForLength else { return }

            // Decode the length byte
            let lengthBits = decodeBits(from: payloadStart, count: lengthBitsCount)
            let lengthBytes = BitConverter.bitsToBytes(lengthBits)
            let length = lengthBytes[0]
            NWLog.debug("[FSKDecoder] length byte: \(length)")

            // Total bits after preamble: 8 (length) + length*8 (data) + 8 (checksum)
            let totalPayloadBits = 8 + Int(length) * 8 + 8
            let totalNeeded = payloadStart + totalPayloadBits * samplesPerBit
            guard sampleBuffer.count >= totalNeeded else { return }

            // Decode all payload bits at once
            let allBits = decodeBits(from: payloadStart, count: totalPayloadBits)
            let allBytes = BitConverter.bitsToBytes(allBits) // [Length][Data...][Checksum]

            NWLog.debug("[FSKDecoder] decoded bytes: \(allBytes)")

            // Attempt frame decode
            if let frame = Frame.decode(from: allBytes) {
                NWLog.debug("[FSKDecoder] ✅ valid frame: \(frame.data)")
                onFrameDecoded?(frame.data)
            } else {
                NWLog.debug("[FSKDecoder] ❌ frame decode failed (checksum or format)")
            }

            // Consume processed samples regardless of success to avoid re-triggering on same data
            let consumed = payloadStart + totalPayloadBits * samplesPerBit
            if consumed <= sampleBuffer.count {
                sampleBuffer.removeFirst(consumed)
            } else {
                sampleBuffer.removeAll()
            }

            // Try again in case there are more frames in the buffer
            attemptDecode()
        }
    }

    // MARK: - Preamble Detection

    /// Slide one bit-window at a time looking for the preamble pattern.
    /// Returns the sample offset of the start of the preamble, or nil.
    private func findPreamble() -> Int? {
        let samplesPerBit = config.samplesPerBit
        let preambleBitCount = preambleBits.count
        let preambleSamples = preambleBitCount * samplesPerBit

        // Don't search past what we could actually decode
        let searchLimit = sampleBuffer.count - preambleSamples
        guard searchLimit >= 0 else { return nil }

        // Step by half a bit window for sub-window alignment tolerance
        let step = max(samplesPerBit / 2, 1)

        for offset in stride(from: 0, through: searchLimit, by: step) {
            let bits = decodeBits(from: offset, count: preambleBitCount)
            if bits == preambleBits {
                return offset
            }
        }

        // If we've searched a lot without finding preamble, trim old samples to avoid unbounded growth.
        let trimThreshold = samplesPerBit * 200 // ~200 bits worth
        if sampleBuffer.count > trimThreshold {
            let toRemove = sampleBuffer.count - preambleSamples
            sampleBuffer.removeFirst(toRemove)
            NWLog.debug("[FSKDecoder] trimmed \(toRemove) old samples")
        }

        return nil
    }

    // MARK: - Bit Decoding via Goertzel

    /// Decode `count` bits starting at the given sample offset.
    private func decodeBits(from offset: Int, count: Int) -> [Bool] {
        let samplesPerBit = config.samplesPerBit
        var bits: [Bool] = []
        bits.reserveCapacity(count)

        for i in 0 ..< count {
            let start = offset + i * samplesPerBit
            let end = start + samplesPerBit
            guard end <= sampleBuffer.count else {
                bits.append(false)
                continue
            }

            let window = Array(sampleBuffer[start ..< end])
            let energy0 = goertzelMagnitude(samples: window, targetFreq: config.freq0, sampleRate: config.sampleRate)
            let energy1 = goertzelMagnitude(samples: window, targetFreq: config.freq1, sampleRate: config.sampleRate)

            let bit = energy1 > energy0
            bits.append(bit)
        }

        return bits
    }

    /// Goertzel algorithm — compute the magnitude of a single frequency bin
    /// over a block of samples. Much cheaper than a full FFT.
    private func goertzelMagnitude(samples: [Float], targetFreq: Double, sampleRate: Double) -> Double {
        let n = samples.count
        guard n > 0 else { return 0 }

        let k = 0.5 + Double(n) * targetFreq / sampleRate
        let omega = 2.0 * Double.pi * k / Double(n)
        let coeff = 2.0 * cos(omega)

        var s0 = 0.0
        var s1 = 0.0
        var s2 = 0.0

        for sample in samples {
            s0 = Double(sample) + coeff * s1 - s2
            s2 = s1
            s1 = s0
        }

        let magnitude = s1 * s1 + s2 * s2 - coeff * s1 * s2
        return magnitude
    }
}
