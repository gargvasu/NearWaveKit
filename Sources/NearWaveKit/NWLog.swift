import Foundation

// MARK: - NWLog

/// Lightweight logger for NearWaveKit debugging.
/// Toggle `isEnabled` to silence all output.
public enum NWLog: Sendable {

    /// Set to `true` to enable debug logging to stdout.
    public static nonisolated(unsafe) var isEnabled: Bool = false

    /// Print a debug message (only when logging is enabled).
    public static func debug(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        print("[NearWaveKit] \(message())")
    }
}
