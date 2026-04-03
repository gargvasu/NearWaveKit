import AVFoundation
import Foundation

// MARK: - WAVReader

/// Reads a WAV file into a Float32 mono sample array using AVAudioFile.
/// Used in tests to reload encoded audio and feed it to the decoder.
enum WAVReader {

    /// Read all samples from a WAV file as mono Float32.
    ///
    /// - Parameter url: Path to the WAV file.
    /// - Returns: Array of Float32 samples.
    static func read(from url: URL) throws -> [Float] {
        let audioFile = try AVAudioFile(forReading: url)
        let frameCount = AVAudioFrameCount(audioFile.length)

        guard frameCount > 0 else {
            throw WAVError.emptyFile
        }

        // Read using the file's own processingFormat (AVAudioFile already converts
        // the native file format to this — typically Float32 at the file's sample rate).
        let processingFormat = audioFile.processingFormat

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: processingFormat,
            frameCapacity: frameCount
        ) else {
            throw WAVError.bufferCreationFailed
        }

        try audioFile.read(into: buffer)

        guard let channelData = buffer.floatChannelData else {
            throw WAVError.bufferCreationFailed
        }

        // Extract channel 0 (mono or left channel of stereo).
        let count = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: count))

        // Debug info
        let maxAmp = samples.map { abs($0) }.max() ?? 0
        let durationMs = Double(count) / processingFormat.sampleRate * 1000
        print("[WAVReader] read \(count) samples (\(String(format: "%.0f", durationMs)) ms) from \(url.lastPathComponent)")
        print("[WAVReader] maxAmplitude=\(String(format: "%.4f", maxAmp)), sampleRate=\(processingFormat.sampleRate), channels=\(processingFormat.channelCount)")

        return samples
    }

    enum WAVError: Error, CustomStringConvertible {
        case emptyFile
        case formatCreationFailed
        case bufferCreationFailed

        var description: String {
            switch self {
            case .emptyFile:            return "WAVReader: file contains no audio frames"
            case .formatCreationFailed: return "WAVReader: failed to create AVAudioFormat"
            case .bufferCreationFailed: return "WAVReader: failed to create AVAudioPCMBuffer"
            }
        }
    }
}
