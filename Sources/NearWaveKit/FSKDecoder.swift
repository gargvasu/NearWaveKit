import Foundation

// MARK: - FSKDecoder

/// Decodes FSK audio samples back into Frames.
///
/// Pipeline:  [Float] samples → frequency detection → bits → bytes → Frame
///
/// Uses the Goertzel algorithm to measure energy at freq0 and freq1 inside
/// the **tone portion** of each symbol window (tone + silence gap).
/// The silence gap and the fade-in / fade-out edges are excluded from
/// analysis to improve noise tolerance on real iOS hardware.
public final class FSKDecoder {

    public var onFrameDecoded: ((_ data: [UInt8]) -> Void)?

    private let config: NSDTConfig

    /// Rolling sample buffer fed from the microphone.
    private var sampleBuffer: [Float] = []

    /// Expected preamble bit pattern (0xAA 0xAA → 1010101010101010).
    private let preambleBits: [Bool]

    /// Samples per full symbol (tone + gap) — the decoder stride.
    private let samplesPerSymbol: Int

    /// Samples of the tone portion only (used for Goertzel window).
    private let samplesPerTone: Int

    /// How many samples to skip at the start of each tone (fade-in margin).
    private let toneMargin: Int

    /// The clean analysis window length inside a tone.
    private let analysisLength: Int

    public init(config: NSDTConfig = .default) {
        self.config = config
        self.preambleBits = BitConverter.bytesToBits(Frame.preamble)
        self.samplesPerSymbol = config.samplesPerSymbol
        self.samplesPerTone = config.samplesPerBit

        // Skip ~10% on each side of the tone to avoid fade-in/fade-out transients.
        let margin = max(config.samplesPerBit / 10, 1)
        self.toneMargin = margin
        self.analysisLength = max(config.samplesPerBit - 2 * margin, margin)

        config.logSummary()
        NWLog.debug("[FSKDecoder] samplesPerSymbol=\(samplesPerSymbol), toneMargin=\(toneMargin), analysisLength=\(analysisLength)")
    }

    // MARK: - Public API

    /// Feed new audio samples into the decoder. Frames are emitted via `onFrameDecoded`.
    public func process(samples: [Float]) {
        sampleBuffer.append(contentsOf: samples)
        attemptDecode()
    }

    /// Synchronous convenience for testing: feed a complete sample buffer and
    /// return the first successfully decoded payload, or `nil`.
    public func processSynchronously(samples: [Float]) -> [UInt8]? {
        var result: [UInt8]?
        let previousCallback = onFrameDecoded
        onFrameDecoded = { data in
            if result == nil { result = data }
        }
        process(samples: samples)
        onFrameDecoded = previousCallback
        return result
    }

    /// Clear internal buffers (e.g. when stopping).
    public func reset() {
        sampleBuffer.removeAll()
    }

    // MARK: - Decode Pipeline

    private func attemptDecode() {
        let preambleBitCount = preambleBits.count
        let preambleSymbols = preambleBitCount * samplesPerSymbol

        // Need at least a full preamble to start searching.
        guard sampleBuffer.count >= preambleSymbols else { return }

        // Step 1 — slide through buffer looking for the preamble
        guard let preambleOffset = findPreamble() else { return }

        NWLog.debug("[FSKDecoder] preamble found at sample offset \(preambleOffset)")

        // Start of payload (after preamble symbols)
        let payloadStart = preambleOffset + preambleSymbols

        // We need at least the length byte (8 symbols)
        let lengthBitsCount = 8
        let minForLength = payloadStart + lengthBitsCount * samplesPerSymbol
        guard sampleBuffer.count >= minForLength else { return }

        // Decode the length byte
        let lengthBits = decodeBits(from: payloadStart, count: lengthBitsCount, label: "length")
        let lengthBytes = BitConverter.bitsToBytes(lengthBits)
        let length = lengthBytes[0]
        NWLog.debug("[FSKDecoder] length byte: \(length)")

        // Sanity — reject obviously bad lengths early.
        guard length > 0 && length <= 32 else {
            NWLog.debug("[FSKDecoder] ⚠️ implausible length \(length), skipping")
            consumeSamples(preambleOffset + samplesPerSymbol)
            attemptDecode()
            return
        }

        // Total symbols after preamble: 8 (length) + length*8 (data) + 8 (checksum)
        let totalPayloadBits = 8 + Int(length) * 8 + 8
        let totalNeeded = payloadStart + totalPayloadBits * samplesPerSymbol
        guard sampleBuffer.count >= totalNeeded else { return }

        // Decode all payload bits at once
        let allBits = decodeBits(from: payloadStart, count: totalPayloadBits, label: "payload")
        let allBytes = BitConverter.bitsToBytes(allBits) // [Length][Data...][Checksum]

        NWLog.debug("[FSKDecoder] decoded bytes: \(allBytes)")

        // Attempt frame decode
        if let frame = Frame.decode(from: allBytes) {
            NWLog.debug("[FSKDecoder] ✅ valid frame: \(frame.data)")
            onFrameDecoded?(frame.data)
        } else {
            NWLog.debug("[FSKDecoder] ❌ frame decode failed (checksum or format)")
        }

        // Consume processed samples regardless of success
        consumeSamples(payloadStart + totalPayloadBits * samplesPerSymbol)

        // Try again for additional frames in the buffer
        attemptDecode()
    }

    /// Safely remove processed samples from the front of the buffer.
    private func consumeSamples(_ count: Int) {
        if count <= sampleBuffer.count {
            sampleBuffer.removeFirst(count)
        } else {
            sampleBuffer.removeAll()
        }
    }

    // MARK: - Preamble Detection

    /// Slide through the buffer looking for the preamble bit pattern.
    /// Returns the sample offset of the start of the preamble, or nil.
    private func findPreamble() -> Int? {
        let preambleBitCount = preambleBits.count
        let preambleSymbols = preambleBitCount * samplesPerSymbol

        let searchLimit = sampleBuffer.count - preambleSymbols
        guard searchLimit >= 0 else { return nil }

        // Step by ¼ symbol for good alignment tolerance without being too slow.
        let step = max(samplesPerSymbol / 4, 1)

        for offset in stride(from: 0, through: searchLimit, by: step) {
            let bits = decodeBitsRaw(from: offset, count: preambleBitCount)
            if bits == preambleBits {
                return offset
            }
        }

        // Trim old samples to prevent unbounded growth.
        // Keep enough for one full preamble so we don't miss a partial one.
        let trimThreshold = samplesPerSymbol * 400
        if sampleBuffer.count > trimThreshold {
            let toRemove = sampleBuffer.count - preambleSymbols
            sampleBuffer.removeFirst(toRemove)
            NWLog.debug("[FSKDecoder] trimmed \(toRemove) old samples")
        }

        return nil
    }

    // MARK: - Bit Decoding via Goertzel

    /// Decode `count` bits starting at the given sample offset.
    /// Each bit occupies `samplesPerSymbol` samples (tone + gap).
    /// Only the center of the tone is analyzed (skipping fade margins).
    /// Logs per-bit energies when `label` is provided.
    private func decodeBits(from offset: Int, count: Int, label: String) -> [Bool] {
        var bits: [Bool] = []
        bits.reserveCapacity(count)

        for i in 0 ..< count {
            let symbolStart = offset + i * samplesPerSymbol
            // Skip the fade-in margin; analyze the clean center of the tone.
            let analysisStart = symbolStart + toneMargin
            let analysisEnd = analysisStart + analysisLength
            guard analysisEnd <= sampleBuffer.count else {
                bits.append(false)
                continue
            }

            let window = Array(sampleBuffer[analysisStart ..< analysisEnd])
            let e0 = goertzelMagnitude(samples: window, targetFreq: config.effectiveFreq0, sampleRate: config.sampleRate)
            let e1 = goertzelMagnitude(samples: window, targetFreq: config.effectiveFreq1, sampleRate: config.sampleRate)

            let bit = e1 > e0
            bits.append(bit)

            NWLog.debug("[FSKDecoder] \(label)[\(i)] e0=\(String(format: "%.1f", e0)) e1=\(String(format: "%.1f", e1)) → \(bit ? "1" : "0")")
        }

        return bits
    }

    /// Fast bit decode without per-bit logging (used during preamble scanning).
    private func decodeBitsRaw(from offset: Int, count: Int) -> [Bool] {
        var bits: [Bool] = []
        bits.reserveCapacity(count)

        for i in 0 ..< count {
            let symbolStart = offset + i * samplesPerSymbol
            let analysisStart = symbolStart + toneMargin
            let analysisEnd = analysisStart + analysisLength
            guard analysisEnd <= sampleBuffer.count else {
                bits.append(false)
                continue
            }

            let window = Array(sampleBuffer[analysisStart ..< analysisEnd])
            let e0 = goertzelMagnitude(samples: window, targetFreq: config.effectiveFreq0, sampleRate: config.sampleRate)
            let e1 = goertzelMagnitude(samples: window, targetFreq: config.effectiveFreq1, sampleRate: config.sampleRate)

            bits.append(e1 > e0)
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
