import Foundation

// MARK: - Checksum

/// Simple XOR-based checksum used for frame integrity validation.
public enum Checksum {

    /// Compute XOR checksum over the length byte and all data bytes.
    public static func compute(length: UInt8, data: [UInt8]) -> UInt8 {
        var xor: UInt8 = length
        for byte in data {
            xor ^= byte
        }
        NWLog.debug("[Checksum] compute: length=\(length), data=\(data) → \(xor)")
        return xor
    }

    /// Convenience: compute checksum for a raw data array (length derived automatically).
    public static func compute(data: [UInt8]) -> UInt8 {
        let length = UInt8(min(data.count, 255))
        return compute(length: length, data: data)
    }

    /// Validate that the checksum matches for the given length, data, and expected checksum.
    public static func validate(length: UInt8, data: [UInt8], checksum: UInt8) -> Bool {
        let expected = compute(length: length, data: data)
        let result = expected == checksum
        NWLog.debug("[Checksum] validate: expected=\(expected), got=\(checksum) → \(result ? "PASS" : "FAIL")")
        return result
    }
}
