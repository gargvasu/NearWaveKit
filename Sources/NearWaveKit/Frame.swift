import Foundation

// MARK: - Frame

/// A generic data frame for ultrasonic transmission.
/// Contains raw byte payload — no app-specific logic.
public struct Frame: Sendable {
    /// Raw data bytes to transmit (max 255 bytes per frame).
    public let data: [UInt8]

    public init(data: [UInt8]) {
        precondition(data.count <= 255, "Frame data must be at most 255 bytes")
        self.data = data
    }
}

// MARK: - Frame Encoding / Decoding

/// Wire format:
///   [Preamble (2 bytes)][Length (1 byte)][Data (N bytes)][Checksum (1 byte)]
///
/// Preamble = 0xAA 0xAA  (10101010 10101010)
/// Length   = UInt8 count of data bytes
/// Data     = raw payload
/// Checksum = XOR of (Length byte) and all data bytes

extension Frame {

    /// Fixed preamble bytes used to mark the start of a frame.
    public static let preamble: [UInt8] = [0xAA, 0xAA]

    /// Encode this frame into a byte sequence ready for FSK modulation.
    public func encode() -> [UInt8] {
        let length = UInt8(data.count)
        let checksum = Checksum.compute(length: length, data: data)

        var bytes: [UInt8] = []
        bytes.append(contentsOf: Frame.preamble)
        bytes.append(length)
        bytes.append(contentsOf: data)
        bytes.append(checksum)

        NWLog.debug("[Frame] encode: preamble=\(Frame.preamble), length=\(length), data=\(data), checksum=\(checksum)")
        return bytes
    }

    /// Attempt to decode a Frame from raw bytes (without preamble).
    /// Expects: [Length][Data...][Checksum]
    /// Returns nil if checksum fails or data is malformed.
    public static func decode(from bytes: [UInt8]) -> Frame? {
        guard bytes.count >= 2 else {
            NWLog.debug("[Frame] decode failed: too few bytes (\(bytes.count))")
            return nil
        }

        let length = bytes[0]
        let expectedTotal = 1 + Int(length) + 1 // length + data + checksum
        guard bytes.count >= expectedTotal else {
            NWLog.debug("[Frame] decode failed: need \(expectedTotal) bytes, have \(bytes.count)")
            return nil
        }

        let data = Array(bytes[1 ..< 1 + Int(length)])
        let checksum = bytes[1 + Int(length)]

        guard Checksum.validate(length: length, data: data, checksum: checksum) else {
            NWLog.debug("[Frame] decode failed: checksum mismatch (got \(checksum))")
            return nil
        }

        NWLog.debug("[Frame] decode OK: length=\(length), data=\(data)")
        return Frame(data: data)
    }
}

// MARK: - Bit Conversion Utilities

/// MSB-first bit conversion used by the FSK layer.
public enum BitConverter {

    /// Convert an array of bytes into an array of bits (MSB first).
    public static func bytesToBits(_ bytes: [UInt8]) -> [Bool] {
        var bits: [Bool] = []
        bits.reserveCapacity(bytes.count * 8)
        for byte in bytes {
            for i in stride(from: 7, through: 0, by: -1) {
                bits.append((byte >> i) & 1 == 1)
            }
        }
        return bits
    }

    /// Convert an array of bits (MSB first) back into bytes.
    /// Pads with trailing false bits if not a multiple of 8.
    public static func bitsToBytes(_ bits: [Bool]) -> [UInt8] {
        var bytes: [UInt8] = []
        var padded = bits
        while padded.count % 8 != 0 {
            padded.append(false)
        }
        for i in stride(from: 0, to: padded.count, by: 8) {
            var byte: UInt8 = 0
            for j in 0 ..< 8 {
                if padded[i + j] {
                    byte |= (1 << (7 - j))
                }
            }
            bytes.append(byte)
        }
        return bytes
    }
}
