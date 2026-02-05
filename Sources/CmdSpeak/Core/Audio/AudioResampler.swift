import AVFoundation
import Foundation
import os

/// Resamples audio to a target sample rate using AVAudioConverter.
/// Defaults to 24kHz for OpenAI Realtime API.
public final class AudioResampler {
    private static let logger = Logger(subsystem: "com.cmdspeak", category: "resampler")

    private let targetSampleRate: Double
    private let targetChannels: AVAudioChannelCount = 1

    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?
    private var lastInputFormat: AVAudioFormat?

    /// Initialize with target sample rate.
    /// - Parameter targetSampleRate: Target sample rate in Hz (default: 24000 for OpenAI Realtime API)
    public init(targetSampleRate: Double = 24000) {
        self.targetSampleRate = targetSampleRate
    }

    public func resample(_ inputBuffer: AVAudioPCMBuffer) -> [Float]? {
        let inputFormat = inputBuffer.format

        if converter == nil || lastInputFormat != inputFormat {
            setupConverter(for: inputFormat)
        }

        guard let converter = converter,
              let outputFormat = outputFormat else {
            return fallbackResample(inputBuffer)
        }

        let outputFrameCapacity = AVAudioFrameCount(
            Double(inputBuffer.frameLength) * targetSampleRate / inputFormat.sampleRate
        )
        guard outputFrameCapacity > 0 else { return nil }

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputFrameCapacity
        ) else {
            return fallbackResample(inputBuffer)
        }

        var error: NSError?
        var inputBufferConsumed = false

        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if inputBufferConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputBufferConsumed = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if status == .error {
            Self.logger.warning("Converter error: \(error?.localizedDescription ?? "unknown")")
            return fallbackResample(inputBuffer)
        }

        guard outputBuffer.frameLength > 0,
              let channelData = outputBuffer.floatChannelData?[0] else {
            return fallbackResample(inputBuffer)
        }

        return Array(UnsafeBufferPointer(start: channelData, count: Int(outputBuffer.frameLength)))
    }

    private func setupConverter(for inputFormat: AVAudioFormat) {
        guard let outputFmt = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            interleaved: false
        ) else {
            Self.logger.error("Failed to create output format")
            return
        }

        guard let conv = AVAudioConverter(from: inputFormat, to: outputFmt) else {
            Self.logger.error("Failed to create converter from \(inputFormat) to \(outputFmt)")
            return
        }

        self.converter = conv
        self.outputFormat = outputFmt
        self.lastInputFormat = inputFormat

        let target = targetSampleRate
        Self.logger.info("Converter: \(inputFormat.sampleRate)Hz → \(target)Hz")
    }

    private func fallbackResample(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let channelData = buffer.floatChannelData?[0] else { return nil }

        let frameLength = Int(buffer.frameLength)
        let sourceSampleRate = buffer.format.sampleRate

        let targetLength = Int(Double(frameLength) * targetSampleRate / sourceSampleRate)
        guard targetLength > 0 else { return nil }

        var resampled = [Float](repeating: 0, count: targetLength)
        let ratio = sourceSampleRate / targetSampleRate

        for i in 0..<targetLength {
            let srcPos = Double(i) * ratio
            let srcIndex = Int(srcPos)
            let frac = Float(srcPos - Double(srcIndex))

            if srcIndex + 1 < frameLength {
                resampled[i] = channelData[srcIndex] * (1 - frac) + channelData[srcIndex + 1] * frac
            } else if srcIndex < frameLength {
                resampled[i] = channelData[srcIndex]
            }
        }

        return resampled
    }

    public func reset() {
        converter?.reset()
    }
}
