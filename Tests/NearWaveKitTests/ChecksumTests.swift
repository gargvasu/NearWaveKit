import XCTest
@testable import NearWaveKit

final class ChecksumTests: XCTestCase {

    // MARK: - Basic Computation

    func testChecksumSingleByte() {
        // checksum = length ^ data[0] = 1 ^ 0x42 = 0x43
        let result = Checksum.compute(length: 1, data: [0x42])
        XCTAssertEqual(result, 0x43)
    }

    func testChecksumMultipleBytes() {
        // length=3, data=[0x01, 0x02, 0x03]
        // checksum = 3 ^ 1 ^ 2 ^ 3 = 3 ^ 1 = 2, 2 ^ 2 = 0, 0 ^ 3 = 3
        let result = Checksum.compute(length: 3, data: [0x01, 0x02, 0x03])
        XCTAssertEqual(result, 3)
    }

    func testChecksumAllZeroData() {
        // length=2, data=[0x00, 0x00]
        // checksum = 2 ^ 0 ^ 0 = 2
        let result = Checksum.compute(length: 2, data: [0x00, 0x00])
        XCTAssertEqual(result, 2)
    }

    func testChecksumAllFF() {
        // length=1, data=[0xFF]
        // checksum = 1 ^ 0xFF = 0xFE
        let result = Checksum.compute(length: 1, data: [0xFF])
        XCTAssertEqual(result, 0xFE)
    }

    // MARK: - Convenience Compute

    func testConvenienceCompute() {
        let data: [UInt8] = [0x10, 0x20]
        let fromConvenience = Checksum.compute(data: data)
        let fromExplicit = Checksum.compute(length: UInt8(data.count), data: data)
        XCTAssertEqual(fromConvenience, fromExplicit)
    }

    // MARK: - Validation

    func testValidateCorrectChecksum() {
        let data: [UInt8] = [0x48, 0x65, 0x6C, 0x6C, 0x6F] // "Hello"
        let length = UInt8(data.count)
        let checksum = Checksum.compute(length: length, data: data)
        XCTAssertTrue(Checksum.validate(length: length, data: data, checksum: checksum))
    }

    func testValidateIncorrectChecksum() {
        let data: [UInt8] = [0x48, 0x65]
        let length = UInt8(data.count)
        let correctChecksum = Checksum.compute(length: length, data: data)
        let wrongChecksum = correctChecksum &+ 1
        XCTAssertFalse(Checksum.validate(length: length, data: data, checksum: wrongChecksum))
    }

    func testValidateFlippedBit() {
        // If one bit in data flips, checksum should fail.
        let data: [UInt8] = [0x42]
        let length: UInt8 = 1
        let checksum = Checksum.compute(length: length, data: data)
        let corruptedData: [UInt8] = [0x43] // one bit flipped
        XCTAssertFalse(Checksum.validate(length: length, data: corruptedData, checksum: checksum))
    }

    // MARK: - Edge Cases

    func testChecksumEmptyData() {
        // length=0, data=[]  →  checksum = 0
        let result = Checksum.compute(length: 0, data: [])
        XCTAssertEqual(result, 0)
    }

    func testChecksumSelfInverse() {
        // XOR is self-inverse: computing checksum twice should return length
        let data: [UInt8] = [0xAB, 0xCD]
        let length: UInt8 = 2
        let c1 = Checksum.compute(length: length, data: data)
        // XOR checksum back with data should give us the length
        var recover: UInt8 = c1
        for byte in data { recover ^= byte }
        XCTAssertEqual(recover, length)
    }
}
