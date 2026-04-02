import XCTest
@testable import NearWaveKit

/// Targeted tests to improve code coverage on paths missed by the core test suite.
/// Each test documents which file/line gap it covers.
final class CoverageBoostTests: XCTestCase {

    // Shared fast test config used across most tests.
    private static let fastConfig = NSDTConfig(
        freq0: 1_800,
        freq1: 2_600,
        amplitude: 1.0,
        bitDuration: 0.02,
        bitGapDuration: 0.005,
        packetGapDuration: 0.01,
        sampleRate: 44_100,
        repeatCount: 1,
        transmissionMode: .audible
    )

    // ──────────────────────────────────────────────
    // MARK: - NWLog coverage (50% → ~100%)
    // ──────────────────────────────────────────────

    func testNWLogEnabledPrintsMessage() {
        // Covers the `print(...)` line inside NWLog.debug when isEnabled == true.
        let previousState = NWLog.isEnabled
        NWLog.isEnabled = true
        NWLog.debug("coverage test message")   // exercises the print path
        NWLog.isEnabled = previousState
    }

    func testNWLogDisabledSkipsMessage() {
        // Covers the early return when isEnabled == false.
        NWLog.isEnabled = false
        NWLog.debug("this should not print")
    }

    // ──────────────────────────────────────────────
    // MARK: - NSDTConfig coverage (78% → ~100%)
    // ──────────────────────────────────────────────

    func testDefaultConfigComputedProperties() {
        // Exercises samplesPerBit, samplesPerBitGap, samplesPerSymbol,
        // samplesPerPacketGap on the DEFAULT config (previously only custom configs were tested).
        let config = NSDTConfig.default
        XCTAssertEqual(config.samplesPerBit, Int(config.sampleRate * config.bitDuration))
        XCTAssertEqual(config.samplesPerBitGap, Int(config.sampleRate * config.bitGapDuration))
        XCTAssertEqual(config.samplesPerSymbol, config.samplesPerBit + config.samplesPerBitGap)
        XCTAssertEqual(config.samplesPerPacketGap, Int(config.sampleRate * config.packetGapDuration))
        XCTAssertEqual(config.transmissionMode, .ultrasonic)
    }

    func testLogSummaryExecutes() {
        // Covers every line of logSummary() — needs logging enabled.
        let previousState = NWLog.isEnabled
        NWLog.isEnabled = true

        let ultraConfig = NSDTConfig(transmissionMode: .ultrasonic)
        ultraConfig.logSummary()

        let audibleConfig = NSDTConfig(transmissionMode: .audible)
        audibleConfig.logSummary()

        NWLog.isEnabled = previousState
    }

    func testEffectiveFrequenciesUltrasonicMode() {
        let config = NSDTConfig(freq0: 17_500, freq1: 18_500, transmissionMode: .ultrasonic)
        XCTAssertEqual(config.effectiveFreq0, 17_500)
        XCTAssertEqual(config.effectiveFreq1, 18_500)
    }

    func testEffectiveFrequenciesAudibleMode() {
        // audible mode ignores user-supplied freq0/freq1
        let config = NSDTConfig(freq0: 99_999, freq1: 99_999, transmissionMode: .audible)
        XCTAssertEqual(config.effectiveFreq0, NSDTConfig.audibleFreq0)
        XCTAssertEqual(config.effectiveFreq1, NSDTConfig.audibleFreq1)
    }

    func testConfigInitStoredProperties() {
        let config = NSDTConfig(
            freq0: 1000, freq1: 2000, amplitude: 0.5,
            bitDuration: 0.03, bitGapDuration: 0.01,
            packetGapDuration: 0.05, sampleRate: 22_050,
            repeatCount: 7, transmissionMode: .audible
        )
        XCTAssertEqual(config.freq0, 1000)
        XCTAssertEqual(config.freq1, 2000)
        XCTAssertEqual(config.amplitude, 0.5)
        XCTAssertEqual(config.bitDuration, 0.03)
        XCTAssertEqual(config.bitGapDuration, 0.01)
        XCTAssertEqual(config.packetGapDuration, 0.05)
        XCTAssertEqual(config.sampleRate, 22_050)
        XCTAssertEqual(config.repeatCount, 7)
        XCTAssertEqual(config.transmissionMode, .audible)
    }

    // ──────────────────────────────────────────────
    // MARK: - Frame coverage improvements (89% → ~95%)
    // ──────────────────────────────────────────────

    func testFrameDecodeLengthExceedsAvailableBytes() {
        // Covers: "need \(expectedTotal) bytes, have \(bytes.count)" branch in Frame.decode
        // Length says 10 bytes, but we only have 3 bytes total.
        let payload: [UInt8] = [10, 0x42, 0x00]  // length=10, only 1 data byte + 1 "checksum"
        let frame = Frame.decode(from: payload)
        XCTAssertNil(frame, "Frame.decode should fail when length exceeds available data")
    }

    func testFrameEncodeEmptyData() {
        // Covers the zero-length data path through encode.
        let frame = Frame(data: [])
        let encoded = frame.encode()
        // [0xAA, 0xAA, length=0, checksum=0]
        XCTAssertEqual(encoded, [0xAA, 0xAA, 0, 0])
    }

    func testFrameDecodeZeroLength() {
        // length=0 with valid checksum → should return empty frame
        // checksum = compute(length: 0, data: []) = 0
        let payload: [UInt8] = [0, 0] // length=0, checksum=0
        let frame = Frame.decode(from: payload)
        XCTAssertNotNil(frame)
        XCTAssertEqual(frame?.data, [])
    }

    // ──────────────────────────────────────────────
    // MARK: - FSKDecoder coverage improvements (86% → ~95%)
    // ──────────────────────────────────────────────

    func testDecoderReset() {
        // Covers: reset() → sampleBuffer.removeAll()
        let decoder = FSKDecoder(config: Self.fastConfig)
        let encoder = FSKEncoder(config: Self.fastConfig)

        let samples = encoder.encode(data: [0x42])
        // Feed partial samples, then reset, then feed nothing — should produce no output.
        let half = samples.count / 2
        decoder.process(samples: Array(samples[0 ..< half]))
        decoder.reset()
        let output = decoder.processSynchronously(samples: [])
        XCTAssertNil(output, "After reset, partial buffer should be cleared")
    }

    func testDecoderIncrementalFeeding() {
        // Covers: the "not enough samples yet" early-return paths in attemptDecode
        // Feed samples in small chunks — decoder should still decode successfully.
        let config = Self.fastConfig
        let encoder = FSKEncoder(config: config)
        let decoder = FSKDecoder(config: config)

        let input: [UInt8] = [0x42]
        let samples = encoder.encode(data: input)

        var received: [UInt8]?
        decoder.onFrameDecoded = { data in
            if received == nil { received = data }
        }

        // Feed in chunks of 256 samples
        let chunkSize = 256
        var offset = 0
        while offset < samples.count {
            let end = min(offset + chunkSize, samples.count)
            decoder.process(samples: Array(samples[offset ..< end]))
            offset = end
        }

        XCTAssertNotNil(received, "Incremental feeding should still decode")
        XCTAssertEqual(received, input)
    }

    func testDecoderTooFewSamplesDoesNothing() {
        // Covers: guard sampleBuffer.count >= preambleSymbols early return
        let config = Self.fastConfig
        let decoder = FSKDecoder(config: config)
        let output = decoder.processSynchronously(samples: [0.1, 0.2, 0.3])
        XCTAssertNil(output, "Tiny buffer should not produce output")
    }

    func testDecoderBufferTrimming() {
        // Covers: the trimming branch in findPreamble when buffer exceeds threshold.
        // Feed a LOT of garbage (> 400 symbols worth) to trigger trimming.
        let config = Self.fastConfig
        let decoder = FSKDecoder(config: config)

        let trimThreshold = config.samplesPerSymbol * 400
        let garbage = [Float](repeating: 0.1, count: trimThreshold + 10000)

        // Enable logging to also cover the NWLog.debug in the trim path.
        let prev = NWLog.isEnabled
        NWLog.isEnabled = true
        decoder.process(samples: garbage)
        NWLog.isEnabled = prev

        // Should not crash, and should not produce output.
        let output = decoder.processSynchronously(samples: [])
        XCTAssertNil(output)
    }

    func testProcessSynchronouslyRestoresCallback() {
        // Covers: the callback save/restore logic in processSynchronously
        let config = Self.fastConfig
        let decoder = FSKDecoder(config: config)

        var externalCallCount = 0
        decoder.onFrameDecoded = { _ in
            externalCallCount += 1
        }

        // processSynchronously should NOT invoke the external callback
        let encoder = FSKEncoder(config: config)
        let samples = encoder.encode(data: [0x42])
        let result = decoder.processSynchronously(samples: samples)

        XCTAssertNotNil(result)
        XCTAssertEqual(externalCallCount, 0, "processSynchronously must not fire the original callback")

        // After processSynchronously, the original callback should be restored.
        // Feed another valid frame through the normal callback path.
        decoder.reset()
        decoder.process(samples: encoder.encode(data: [0x07]))
        XCTAssertEqual(externalCallCount, 1, "Original callback should be restored after processSynchronously")
    }

    func testDecoderConsumeSamplesOverflow() {
        // Covers: consumeSamples else branch (count > sampleBuffer.count → removeAll)
        // This is an internal edge case. We trigger it by feeding just enough for a
        // preamble + length but with corrupted length that causes over-consumption.
        // Mostly a "does not crash" test.
        let config = Self.fastConfig
        let decoder = FSKDecoder(config: config)

        let encoder = FSKEncoder(config: config)
        let samples = encoder.encode(data: [0x01])
        // Truncate samples so consumeSamples gets a count > actual buffer
        let truncated = Array(samples[0 ..< samples.count * 3 / 4])

        let output = decoder.processSynchronously(samples: truncated)
        // May or may not decode, but must not crash.
        _ = output
    }

    // ──────────────────────────────────────────────
    // MARK: - FSKEncoder coverage improvements (96% → ~100%)
    // ──────────────────────────────────────────────

    func testEncodeFrameDirectly() {
        // Covers: encode(frame:) called directly instead of through encode(data:)
        let config = Self.fastConfig
        let encoder = FSKEncoder(config: config)

        let frame = Frame(data: [0xAA])
        let samples = encoder.encode(frame: frame)
        XCTAssertGreaterThan(samples.count, 0)

        // Verify it decodes correctly
        let decoder = FSKDecoder(config: config)
        let output = decoder.processSynchronously(samples: samples)
        XCTAssertEqual(output, [0xAA])
    }

    func testEncodeUltrasonicMode() {
        // Covers: the ultrasonic frequency path in encoder generatePacket
        let config = NSDTConfig(
            freq0: 17_500,
            freq1: 18_500,
            amplitude: 1.0,
            bitDuration: 0.02,
            bitGapDuration: 0.005,
            packetGapDuration: 0.01,
            sampleRate: 44_100,
            repeatCount: 1,
            transmissionMode: .ultrasonic
        )
        let encoder = FSKEncoder(config: config)
        let decoder = FSKDecoder(config: config)

        let input: [UInt8] = [0x42]
        let samples = encoder.encode(data: input)
        XCTAssertGreaterThan(samples.count, 0)

        let output = decoder.processSynchronously(samples: samples)
        XCTAssertNotNil(output)
        XCTAssertEqual(output, input)
    }

    func testEncodeMultipleRepeatsProducesLargerBuffer() {
        // Covers: the packet-gap insertion loop for i > 0
        let config1 = NSDTConfig(
            freq0: 1_800, freq1: 2_600,
            bitDuration: 0.02, bitGapDuration: 0.005,
            packetGapDuration: 0.01,
            sampleRate: 44_100, repeatCount: 1,
            transmissionMode: .audible
        )
        let config3 = NSDTConfig(
            freq0: 1_800, freq1: 2_600,
            bitDuration: 0.02, bitGapDuration: 0.005,
            packetGapDuration: 0.01,
            sampleRate: 44_100, repeatCount: 3,
            transmissionMode: .audible
        )

        let enc1 = FSKEncoder(config: config1)
        let enc3 = FSKEncoder(config: config3)

        let samples1 = enc1.encode(data: [0x42])
        let samples3 = enc3.encode(data: [0x42])

        // 3 repeats should be > 3× single (because of packet gaps)
        // At minimum, it should be close to 3× the single pass.
        XCTAssertGreaterThan(samples3.count, samples1.count * 2)
    }

    // ──────────────────────────────────────────────
    // MARK: - Encoder with logging enabled (covers NWLog paths in encoder)
    // ──────────────────────────────────────────────

    func testEncoderWithLoggingEnabled() {
        let prev = NWLog.isEnabled
        NWLog.isEnabled = true

        let config = Self.fastConfig
        let encoder = FSKEncoder(config: config)
        let samples = encoder.encode(data: [0x42])
        XCTAssertGreaterThan(samples.count, 0)

        NWLog.isEnabled = prev
    }

    func testDecoderWithLoggingEnabled() {
        let prev = NWLog.isEnabled
        NWLog.isEnabled = true

        let config = Self.fastConfig
        let encoder = FSKEncoder(config: config)
        let decoder = FSKDecoder(config: config)

        let samples = encoder.encode(data: [0x42])
        let output = decoder.processSynchronously(samples: samples)
        XCTAssertEqual(output, [0x42])

        NWLog.isEnabled = prev
    }

    // ──────────────────────────────────────────────
    // MARK: - TransmissionMode coverage
    // ──────────────────────────────────────────────

    func testTransmissionModeRawValues() {
        XCTAssertEqual(TransmissionMode.ultrasonic.rawValue, "ultrasonic")
        XCTAssertEqual(TransmissionMode.audible.rawValue, "audible")
    }

    // ──────────────────────────────────────────────
    // MARK: - Checksum with logging (covers debug prints)
    // ──────────────────────────────────────────────

    func testChecksumWithLoggingEnabled() {
        let prev = NWLog.isEnabled
        NWLog.isEnabled = true

        let cs = Checksum.compute(length: 1, data: [0x42])
        XCTAssertEqual(cs, 0x43)
        XCTAssertTrue(Checksum.validate(length: 1, data: [0x42], checksum: cs))
        XCTAssertFalse(Checksum.validate(length: 1, data: [0x42], checksum: 0x00))

        NWLog.isEnabled = prev
    }

    func testFrameEncodeDecodeWithLoggingEnabled() {
        let prev = NWLog.isEnabled
        NWLog.isEnabled = true

        let frame = Frame(data: [0x10, 0x20])
        let encoded = frame.encode()
        let payload = Array(encoded[2...])
        let decoded = Frame.decode(from: payload)
        XCTAssertEqual(decoded?.data, [0x10, 0x20])

        // Also test failure path with logging
        let bad = Frame.decode(from: [])
        XCTAssertNil(bad)
        let bad2 = Frame.decode(from: [5, 0x01]) // length=5, not enough data
        XCTAssertNil(bad2)
        let bad3 = Frame.decode(from: [1, 0x42, 0xFF]) // wrong checksum
        XCTAssertNil(bad3)

        NWLog.isEnabled = prev
    }
}
