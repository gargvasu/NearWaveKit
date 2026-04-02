import Foundation

// MARK: - NSDTService

/// Public protocol for the Near-Sound Data Transfer service.
/// Consumers only need to interact with this interface.
public protocol NSDTService {

    /// Callback invoked when a valid data payload is received over audio.
    /// Called on an internal queue — dispatch to main if needed.
    var onDataReceived: (([UInt8]) -> Void)? { get set }

    /// Start listening for incoming ultrasonic data.
    func startListening()

    /// Stop listening.
    func stopListening()

    /// Transmit raw bytes over ultrasonic audio.
    func send(data: [UInt8])
}
