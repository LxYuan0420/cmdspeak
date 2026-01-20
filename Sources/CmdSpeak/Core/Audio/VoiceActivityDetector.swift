import AVFoundation
import Foundation

/// Protocol for voice activity detection.
public protocol VoiceActivityDetecting {
    var onSpeechStart: (() -> Void)? { get set }
    var onSpeechEnd: (() -> Void)? { get set }

    func process(buffer: AVAudioPCMBuffer)
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
        let rms = calculateRMS(samples: channelData, count: frameLength)

        samplesProcessed += frameLength

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

    private func calculateRMS(samples: UnsafePointer<Float>, count: Int) -> Float {
        var sum: Float = 0
        for i in 0..<count {
            sum += samples[i] * samples[i]
        }
        return sqrt(sum / Float(count))
    }
}
