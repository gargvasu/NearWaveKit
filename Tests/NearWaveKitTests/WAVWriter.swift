import AVFoundation
import Foundation

// MARK: - WAVWriter

/// Writes Float32 mono audio samples to a WAV file using AVAudioFile.
/// Used in tests to simulate the speaker → file → microphone pipeline.
enum WAVWriter {

    /// Write mono Float32 samples to a WAV file at the given URL.
    ///
    /// - Parameters:
    ///   - samples: Array of Float32 PCM samples.
    ///   - url: Destination file URL (will be overwritten if it exists).
    ///   - sampleRate: Sample rate in Hz (must match the encoder config).
    static func write(samples: [Float], to url: URL, sampleRate: Double) throws {
        guard !samples.isEmpty else {
            throw WAVError.emptySamples
        }

        // Define the file format: 32-bit float, mono, at the requested sample rate.
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw WAVError.formatCreationFailed
        }

        // Create the output file (WAV container).
        let audioFile = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        // Allocate a PCM buffer and copy our samples into it.
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            throw WAVError.bufferCreationFailed
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)

        guard let channelData = buffer.floatChannelData else {
            throw WAVError.bufferCreationFailed
        }

        samples.withUnsafeBufferPointer { src in
            channelData[0].initialize(from: src.baseAddress!, count: samples.count)
        }

        try audioFile.write(from: buffer)

        // Debug info
        let maxAmp = samples.map { abs($0) }.max() ?? 0
        let durationMs = Double(samples.count) / sampleRate * 1000
        print("[WAVWriter] wrote \(samples.count) samples (\(String(format: "%.0f", durationMs)) ms) to \(url.lastPathComponent)")
        print("[WAVWriter] maxAmplitude=\(String(format: "%.4f", maxAmp)), sampleRate=\(sampleRate)")
    }

    enum WAVError: Error, CustomStringConvertible {
        case emptySamples
        case formatCreationFailed
        case bufferCreationFailed

        var description: String {
            switch self {
            case .emptySamples:         return "WAVWriter: samples array is empty"
            case .formatCreationFailed: return "WAVWriter: failed to create AVAudioFormat"
            case .bufferCreationFailed: return "WAVWriter: failed to create AVAudioPCMBuffer"
            }
        }
    }
}
