import Foundation

// MARK: - NSDTConfig

/// Configuration for the Near-Sound Data Transfer system.
/// All frequency values are in Hz, durations in seconds.
///
/// Defaults are tuned for **real-world iPhone speaker → air → iPhone microphone**
/// communication.  Slower bit rates and silence gaps prevent iOS AGC / noise
/// suppression from eating the signal.
public struct NSDTConfig: Sendable {

    /// Frequency used to represent a binary 0 in ultrasonic mode (Hz).
    public let freq0: Double

    /// Frequency used to represent a binary 1 in ultrasonic mode (Hz).
    public let freq1: Double

    /// Amplitude of the generated sine wave (0.0 – 1.0).
    /// Use 1.0 for maximum signal strength over air.
    public let amplitude: Float

    /// Duration of the tone for each bit in seconds.
    /// Longer = more reliable over speaker-to-mic.
    public let bitDuration: Double

    /// Duration of silence inserted **after every bit** (seconds).
    /// Prevents iOS DSP from treating the signal as continuous noise.
    public let bitGapDuration: Double

    /// Duration of silence inserted **after each full packet** (seconds).
    /// Separates repeated transmissions so the decoder can re-sync.
    public let packetGapDuration: Double

    /// Audio sample rate in Hz.
    public let sampleRate: Double

    /// Number of times the full frame is transmitted back-to-back.
    public let repeatCount: Int

    /// Transmission mode — `.ultrasonic` (default) or `.audible` (debug/testing).
    public let transmissionMode: TransmissionMode

    // MARK: - Audible-mode frequency constants

    /// Frequency for bit-0 in audible mode (Hz).  Chosen for clear speaker
    /// reproduction and easy debugging with headphones.
    public static let audibleFreq0: Double = 1_800

    /// Frequency for bit-1 in audible mode (Hz).
    public static let audibleFreq1: Double = 2_600

    public init(
        freq0: Double = 17_500,
        freq1: Double = 18_500,
        amplitude: Float = 1.0,
        bitDuration: Double = 0.06,
        bitGapDuration: Double = 0.015,
        packetGapDuration: Double = 0.12,
        sampleRate: Double = 44_100,
        repeatCount: Int = 5,
        transmissionMode: TransmissionMode = .ultrasonic
    ) {
        self.freq0 = freq0
        self.freq1 = freq1
        self.amplitude = amplitude
        self.bitDuration = bitDuration
        self.bitGapDuration = bitGapDuration
        self.packetGapDuration = packetGapDuration
        self.sampleRate = sampleRate
        self.repeatCount = repeatCount
        self.transmissionMode = transmissionMode
    }

    // MARK: - Effective Frequencies

    /// The actual freq-0 used by encoder/decoder, respecting `transmissionMode`.
    public var effectiveFreq0: Double {
        switch transmissionMode {
        case .ultrasonic: return freq0
        case .audible:    return Self.audibleFreq0
        }
    }

    /// The actual freq-1 used by encoder/decoder, respecting `transmissionMode`.
    public var effectiveFreq1: Double {
        switch transmissionMode {
        case .ultrasonic: return freq1
        case .audible:    return Self.audibleFreq1
        }
    }

    // MARK: - Derived Sample Counts

    /// Number of audio samples for the tone portion of one bit.
    public var samplesPerBit: Int {
        Int(sampleRate * bitDuration)
    }

    /// Number of silence samples inserted after each bit tone.
    public var samplesPerBitGap: Int {
        Int(sampleRate * bitGapDuration)
    }

    /// Total samples per symbol (tone + gap).
    /// This is the stride the decoder uses when walking through the buffer.
    public var samplesPerSymbol: Int {
        samplesPerBit + samplesPerBitGap
    }

    /// Number of silence samples inserted after a full packet.
    public var samplesPerPacketGap: Int {
        Int(sampleRate * packetGapDuration)
    }

    /// Default configuration — tuned for real-world iOS speaker-to-mic transfer.
    public static let `default` = NSDTConfig()

    /// Dump all effective parameters to the debug log.
    public func logSummary() {
        NWLog.debug("─── NSDTConfig ───")
        NWLog.debug("  mode            : \(transmissionMode.rawValue)")
        NWLog.debug("  effectiveFreq0  : \(effectiveFreq0) Hz")
        NWLog.debug("  effectiveFreq1  : \(effectiveFreq1) Hz")
        NWLog.debug("  amplitude       : \(amplitude)")
        NWLog.debug("  bitDuration     : \(bitDuration) s")
        NWLog.debug("  bitGapDuration  : \(bitGapDuration) s")
        NWLog.debug("  packetGapDuration: \(packetGapDuration) s")
        NWLog.debug("  sampleRate      : \(sampleRate) Hz")
        NWLog.debug("  samplesPerBit   : \(samplesPerBit)")
        NWLog.debug("  samplesPerBitGap: \(samplesPerBitGap)")
        NWLog.debug("  samplesPerSymbol: \(samplesPerSymbol)")
        NWLog.debug("  repeatCount     : \(repeatCount)")
        NWLog.debug("──────────────────")
    }
}
