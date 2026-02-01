import AVFoundation
import Foundation

/// Protocol for voice activity detection.
public protocol VoiceActivityDetecting {
    var onSpeechStart: (() -> Void)? { get set }
    var onSpeechEnd: (() -> Void)? { get set }

    func process(buffer: AVAudioPCMBuffer)
    func processSamples(_ samples: [Float])
    func reset()
}

/// Simple energy-based voice activity detector.
/// Detects speech onset and end based on audio energy levels.
public final class VoiceActivityDetector: VoiceActivityDetecting {
    public var onSpeechStart: (() -> Void)?
    public var onSpeechEnd: (() -> Void)?

    private let energyThreshold: Float
    private let silenceDuration: TimeInterval
    private let sampleRate: Double

    private var isSpeaking = false
    private var silenceStartTime: Date?
    private var samplesProcessed: Int = 0

    /// Initialize the VAD.
    /// - Parameters:
    ///   - energyThreshold: RMS threshold for speech detection (default: 0.01)
    ///   - silenceDuration: Duration of silence before speech end (default: 0.5s)
    ///   - sampleRate: Audio sample rate (default: 16000)
    public init(
        energyThreshold: Float = 0.01,
        silenceDuration: TimeInterval = 0.5,
        sampleRate: Double = 16000
    ) {
        self.energyThreshold = energyThreshold
        self.silenceDuration = silenceDuration
        self.sampleRate = sampleRate
    }

    public func process(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
        processSamples(samples)
    }

    public func processSamples(_ samples: [Float]) {
        guard !samples.isEmpty else { return }

        let rms = calculateRMSFromArray(samples)
        samplesProcessed += samples.count

        if rms > energyThreshold {
            if !isSpeaking {
                isSpeaking = true
                silenceStartTime = nil
                onSpeechStart?()
            } else {
                silenceStartTime = nil
            }
        } else {
            if isSpeaking {
                if silenceStartTime == nil {
                    silenceStartTime = Date()
                } else if let start = silenceStartTime,
                          Date().timeIntervalSince(start) >= silenceDuration {
                    isSpeaking = false
                    silenceStartTime = nil
                    onSpeechEnd?()
                }
            }
        }
    }

    public func reset() {
        isSpeaking = false
        silenceStartTime = nil
        samplesProcessed = 0
    }

    private func calculateRMSFromArray(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        return sqrt(sum / Float(samples.count))
    }
}
