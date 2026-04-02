import Foundation

// MARK: - TransmissionMode

/// Selects the frequency range used for FSK encoding and decoding.
///
/// - `ultrasonic`: Near-ultrasonic frequencies (default, inaudible to most humans).
/// - `audible`: Low-frequency tones useful for debugging — you can *hear* the signal.
public enum TransmissionMode: String, Sendable {
    case ultrasonic
    case audible
}
