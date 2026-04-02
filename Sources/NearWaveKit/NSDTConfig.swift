import Foundation

// MARK: - NSDTConfig

/// Configuration for the Near-Sound Data Transfer system.
/// All frequency values are in Hz, durations in seconds.
public struct NSDTConfig: Sendable {

    /// Frequency used to represent a binary 0 (Hz).
    public let freq0: Double

    /// Frequency used to represent a binary 1 (Hz).
    public let freq1: Double

    /// Amplitude of the generated sine wave (0.0 – 1.0).
    public let amplitude: Float

    /// Duration of each bit in seconds.
    public let bitDuration: Double

    /// Audio sample rate in Hz.
    public let sampleRate: Double

    /// Number of times the full frame is transmitted back-to-back.
    public let repeatCount: Int

    public init(
        freq0: Double = 17_500,
        freq1: Double = 18_200,
        amplitude: Float = 0.8,
        bitDuration: Double = 0.01,
        sampleRate: Double = 44_100,
        repeatCount: Int = 3
    ) {
        self.freq0 = freq0
        self.freq1 = freq1
        self.amplitude = amplitude
        self.bitDuration = bitDuration
        self.sampleRate = sampleRate
        self.repeatCount = repeatCount
    }

    /// Number of audio samples per bit.
    public var samplesPerBit: Int {
        Int(sampleRate * bitDuration)
    }

    /// Default configuration — good starting point for near-field ultrasonic transfer.
    public static let `default` = NSDTConfig()
}
