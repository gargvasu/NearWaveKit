import XCTest
@testable import NearWaveKit

final class FrameTests: XCTestCase {

    // MARK: - BitConverter Round-Trip

    func testBytesToBitsAndBack_singleByte() {
        let original: [UInt8] = [0b10110011]
        let bits = BitConverter.bytesToBits(original)
        XCTAssertEqual(bits.count, 8)
        // MSB first: 1,0,1,1,0,0,1,1
        XCTAssertEqual(bits, [true, false, true, true, false, false, true, true])
        let roundTripped = BitConverter.bitsToBytes(bits)
        XCTAssertEqual(roundTripped, original)
    }

    func testBytesToBitsAndBack_multipleBytes() {
        let original: [UInt8] = [0x48, 0x65, 0x6C] // "Hel"
        let bits = BitConverter.bytesToBits(original)
        XCTAssertEqual(bits.count, 24)
        let roundTripped = BitConverter.bitsToBytes(bits)
        XCTAssertEqual(roundTripped, original)
    }

    func testBytesToBitsAndBack_allZeros() {
        let original: [UInt8] = [0x00]
        let bits = BitConverter.bytesToBits(original)
        XCTAssertTrue(bits.allSatisfy { $0 == false })
        let roundTripped = BitConverter.bitsToBytes(bits)
        XCTAssertEqual(roundTripped, original)
    }

    func testBytesToBitsAndBack_allOnes() {
        let original: [UInt8] = [0xFF]
        let bits = BitConverter.bytesToBits(original)
        XCTAssertTrue(bits.allSatisfy { $0 == true })
        let roundTripped = BitConverter.bitsToBytes(bits)
        XCTAssertEqual(roundTripped, original)
    }

    func testBitsToBytes_padsIncompleteByte() {
        // 5 bits → should pad to 8, giving 1 byte
        let bits: [Bool] = [true, false, true, false, true]
        let bytes = BitConverter.bitsToBytes(bits)
        XCTAssertEqual(bytes.count, 1)
        // 10101_000 = 0b10101000 = 0xA8
        XCTAssertEqual(bytes[0], 0xA8)
    }

    func testEmptyBits() {
        let bits = BitConverter.bytesToBits([])
        XCTAssertTrue(bits.isEmpty)
        let bytes = BitConverter.bitsToBytes([])
        XCTAssertTrue(bytes.isEmpty)
    }

    // MARK: - Frame Encode / Decode

    func testFrameEncodeFormat() {
        let frame = Frame(data: [0x42])
        let encoded = frame.encode()
        // [0xAA, 0xAA, length=1, 0x42, checksum]
        XCTAssertEqual(encoded[0], 0xAA)
        XCTAssertEqual(encoded[1], 0xAA)
        XCTAssertEqual(encoded[2], 1)       // length
        XCTAssertEqual(encoded[3], 0x42)    // data
        // checksum = 1 ^ 0x42 = 0x43
        XCTAssertEqual(encoded[4], 0x43)
        XCTAssertEqual(encoded.count, 5)
    }

    func testFrameDecodeValidPayload() {
        // Simulate what the decoder sees after stripping preamble:
        // [Length][Data...][Checksum]
        let data: [UInt8] = [0x42]
        let length: UInt8 = 1
        let checksum = Checksum.compute(length: length, data: data)
        let payload: [UInt8] = [length] + data + [checksum]

        let frame = Frame.decode(from: payload)
        XCTAssertNotNil(frame)
        XCTAssertEqual(frame?.data, [0x42])
    }

    func testFrameDecodeInvalidChecksum() {
        let payload: [UInt8] = [1, 0x42, 0xFF] // wrong checksum
        let frame = Frame.decode(from: payload)
        XCTAssertNil(frame)
    }

    func testFrameDecodeTooShort() {
        let frame = Frame.decode(from: [])
        XCTAssertNil(frame)

        let frame2 = Frame.decode(from: [1]) // just length, no data or checksum
        XCTAssertNil(frame2)
    }

    func testFrameRoundTrip_multipleBytes() {
        let original: [UInt8] = [0x48, 0x65, 0x6C, 0x6C, 0x6F] // "Hello"
        let frame = Frame(data: original)
        let encoded = frame.encode()

        // Strip preamble (first 2 bytes) for decode
        let payload = Array(encoded[2...])
        let decoded = Frame.decode(from: payload)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.data, original)
    }

    func testFrameRoundTrip_singleByte() {
        let original: [UInt8] = [0xAB]
        let frame = Frame(data: original)
        let encoded = frame.encode()
        let payload = Array(encoded[2...])
        let decoded = Frame.decode(from: payload)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.data, original)
    }

    // MARK: - Preamble

    func testPreambleIsCorrect() {
        XCTAssertEqual(Frame.preamble, [0xAA, 0xAA])
    }

    func testPreambleBitPattern() {
        let bits = BitConverter.bytesToBits(Frame.preamble)
        // 0xAA = 10101010 → alternating true/false
        for (i, bit) in bits.enumerated() {
            XCTAssertEqual(bit, i % 2 == 0, "Bit \(i) should be \(i % 2 == 0)")
        }
    }
}
