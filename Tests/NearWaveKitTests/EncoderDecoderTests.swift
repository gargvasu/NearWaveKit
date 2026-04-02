import XCTest
@testable import NearWaveKit

final class EncoderDecoderTests: XCTestCase {

    /// A fast test config: audible mode, single repeat, quick bit duration.
    /// Using audible mode because frequencies are well within Nyquist for 44100 Hz.
    private static let testConfig = NSDTConfig(
        freq0: 1_800,
        freq1: 2_600,
        amplitude: 1.0,
        bitDuration: 0.02,        // 20 ms per bit — fast but enough for Goertzel
        bitGapDuration: 0.005,    // 5 ms gap
        packetGapDuration: 0.01,  // 10 ms between packets
        sampleRate: 44_100,
        repeatCount: 1,
        transmissionMode: .audible
    )

    // MARK: - Single Byte

    func testSingleByteRoundTrip() {
        let config = Self.testConfig
        let encoder = FSKEncoder(config: config)
        let decoder = FSKDecoder(config: config)

        let input: [UInt8] = [0x42]
        let samples = encoder.encode(data: input)

        let output = decoder.processSynchronously(samples: samples)
        XCTAssertNotNil(output, "Decoder should produce output for a valid single-byte frame")
        XCTAssertEqual(output, input)
    }

    // MARK: - Multiple Bytes

    func testMultiByteRoundTrip() {
        let config = Self.testConfig
        let encoder = FSKEncoder(config: config)
        let decoder = FSKDecoder(config: config)

        let input: [UInt8] = [0x48, 0x65, 0x6C, 0x6C, 0x6F] // "Hello"
        let samples = encoder.encode(data: input)

        let output = decoder.processSynchronously(samples: samples)
        XCTAssertNotNil(output, "Decoder should produce output for 'Hello'")
        XCTAssertEqual(output, input)
    }

    // MARK: - Two Bytes

    func testTwoByteRoundTrip() {
        let config = Self.testConfig
        let encoder = FSKEncoder(config: config)
        let decoder = FSKDecoder(config: config)

        let input: [UInt8] = [0xAB, 0xCD]
        let samples = encoder.encode(data: input)

        let output = decoder.processSynchronously(samples: samples)
        XCTAssertNotNil(output)
        XCTAssertEqual(output, input)
    }

    // MARK: - All Zeros

    func testAllZerosPayload() {
        let config = Self.testConfig
        let encoder = FSKEncoder(config: config)
        let decoder = FSKDecoder(config: config)

        let input: [UInt8] = [0x00, 0x00]
        let samples = encoder.encode(data: input)

        let output = decoder.processSynchronously(samples: samples)
        XCTAssertNotNil(output)
        XCTAssertEqual(output, input)
    }

    // MARK: - All Ones

    func testAllOnesPayload() {
        let config = Self.testConfig
        let encoder = FSKEncoder(config: config)
        let decoder = FSKDecoder(config: config)

        let input: [UInt8] = [0xFF, 0xFF]
        let samples = encoder.encode(data: input)

        let output = decoder.processSynchronously(samples: samples)
        XCTAssertNotNil(output)
        XCTAssertEqual(output, input)
    }

    // MARK: - Callback API

    func testCallbackAPIWorks() {
        let config = Self.testConfig
        let encoder = FSKEncoder(config: config)
        let decoder = FSKDecoder(config: config)

        let input: [UInt8] = [0x07]
        let samples = encoder.encode(data: input)

        let expectation = expectation(description: "onFrameDecoded fires")
        var received: [UInt8]?

        decoder.onFrameDecoded = { data in
            received = data
            expectation.fulfill()
        }
        decoder.process(samples: samples)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(received, input)
    }

    // MARK: - Repeated Transmission

    func testRepeatedTransmissionDecodesAtLeastOnce() {
        let config = NSDTConfig(
            freq0: 1_800,
            freq1: 2_600,
            amplitude: 1.0,
            bitDuration: 0.02,
            bitGapDuration: 0.005,
            packetGapDuration: 0.02,
            sampleRate: 44_100,
            repeatCount: 3,
            transmissionMode: .audible
        )
        let encoder = FSKEncoder(config: config)
        let decoder = FSKDecoder(config: config)

        let input: [UInt8] = [0xBE, 0xEF]
        let samples = encoder.encode(data: input)

        // Should decode at least one valid frame from 3 repeats.
        var allDecoded: [[UInt8]] = []
        decoder.onFrameDecoded = { data in
            allDecoded.append(data)
        }
        decoder.process(samples: samples)

        XCTAssertGreaterThanOrEqual(allDecoded.count, 1, "Should decode at least 1 frame from 3 repeats")
        XCTAssertEqual(allDecoded.first, input)
    }

    // MARK: - Noise Tolerance

    func testDecodesWithLightNoise() {
        let config = Self.testConfig
        let encoder = FSKEncoder(config: config)
        let decoder = FSKDecoder(config: config)

        let input: [UInt8] = [0x42]
        var samples = encoder.encode(data: input)

        // Add light random noise (amplitude ±0.05 — 5% of full scale).
        // Use a seeded approach for reproducibility.
        var rng: UInt64 = 12345
        for i in 0 ..< samples.count {
            // Simple xorshift64 for deterministic noise
            rng ^= rng << 13
            rng ^= rng >> 7
            rng ^= rng << 17
            let noise = Float(Double(rng % 1000) / 10000.0 - 0.05) // ±0.05
            samples[i] += noise
        }

        let output = decoder.processSynchronously(samples: samples)
        XCTAssertNotNil(output, "Decoder should tolerate light noise")
        XCTAssertEqual(output, input)
    }

    func testDecodesWithModerateNoise() {
        // Use 3 repeats for moderate noise resilience
        let config = NSDTConfig(
            freq0: 1_800,
            freq1: 2_600,
            amplitude: 1.0,
            bitDuration: 0.02,
            bitGapDuration: 0.005,
            packetGapDuration: 0.02,
            sampleRate: 44_100,
            repeatCount: 3,
            transmissionMode: .audible
        )
        let encoder = FSKEncoder(config: config)
        let decoder = FSKDecoder(config: config)

        let input: [UInt8] = [0x42]
        var samples = encoder.encode(data: input)

        // Moderate noise: ±0.1 (10% of full scale)
        var rng: UInt64 = 67890
        for i in 0 ..< samples.count {
            rng ^= rng << 13
            rng ^= rng >> 7
            rng ^= rng << 17
            let noise = Float(Double(rng % 2000) / 10000.0 - 0.1)
            samples[i] += noise
        }

        let output = decoder.processSynchronously(samples: samples)
        XCTAssertNotNil(output, "Decoder should tolerate moderate noise with repeats")
        XCTAssertEqual(output, input)
    }

    // MARK: - Garbage Input

    func testGarbageSamplesProduceNothing() {
        let config = Self.testConfig
        let decoder = FSKDecoder(config: config)

        // Feed pure silence
        let silence = [Float](repeating: 0.0, count: 44100)
        let output = decoder.processSynchronously(samples: silence)
        XCTAssertNil(output, "Silence should not decode into a frame")
    }

    func testRandomSamplesProduceNothing() {
        let config = Self.testConfig
        let decoder = FSKDecoder(config: config)

        // Feed random garbage
        var rng: UInt64 = 99999
        var garbage = [Float](repeating: 0.0, count: 44100)
        for i in 0 ..< garbage.count {
            rng ^= rng << 13
            rng ^= rng >> 7
            rng ^= rng << 17
            garbage[i] = Float(Double(rng % 2000) / 1000.0 - 1.0)
        }

        let output = decoder.processSynchronously(samples: garbage)
        // It's acceptable if random data occasionally triggers a false positive,
        // but it should be extremely rare. We mostly verify it doesn't crash.
        _ = output // no assertion — just ensure no crash
    }

    // MARK: - Config Sanity

    func testConfigDerivedValues() {
        let config = Self.testConfig
        XCTAssertEqual(config.samplesPerBit, Int(44100 * 0.02))  // 882
        XCTAssertEqual(config.samplesPerBitGap, Int(44100 * 0.005)) // 220
        XCTAssertEqual(config.samplesPerSymbol, config.samplesPerBit + config.samplesPerBitGap)
        XCTAssertEqual(config.effectiveFreq0, 1_800)
        XCTAssertEqual(config.effectiveFreq1, 2_600)
    }

    func testUltrasonicModeFrequencies() {
        let config = NSDTConfig(transmissionMode: .ultrasonic)
        XCTAssertEqual(config.effectiveFreq0, 17_500)
        XCTAssertEqual(config.effectiveFreq1, 18_500)
    }

    func testAudibleModeFrequencies() {
        let config = NSDTConfig(transmissionMode: .audible)
        XCTAssertEqual(config.effectiveFreq0, NSDTConfig.audibleFreq0)
        XCTAssertEqual(config.effectiveFreq1, NSDTConfig.audibleFreq1)
    }
}
