import AVFoundation
import Foundation
import os

/// Captures audio from the default input device using AVAudioEngine.
/// Provides audio buffers via callback for transcription.
///
/// Note: `onAudioBuffer` is called on a dedicated audio callback queue,
/// not the main thread. Callers must dispatch to main if needed.
public final class AudioCaptureManager {
    private static let logger = Logger(subsystem: "com.cmdspeak", category: "audio-capture")

    private var audioEngine: AVAudioEngine?
    private let bufferSize: AVAudioFrameCount = 4096
    private let callbackQueue = DispatchQueue(label: "com.cmdspeak.audio.callback", qos: .userInteractive)

    public private(set) var isRecording = false
    public var onAudioBuffer: (@Sendable (_ buffer: AVAudioPCMBuffer) -> Void)?

    public init() {}

    public func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    public func startRecording() async throws {
        guard !isRecording else { return }

        let permission = await requestPermission()
        guard permission else {
            throw AudioCaptureError.permissionDenied
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        
        _ = inputNode.inputFormat(forBus: 0)
        
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioCaptureError.noInputDevice
        }

        Self.logger.info("Audio format: \(format.sampleRate)Hz, \(format.channelCount) ch")

        let callback = onAudioBuffer
        let queue = callbackQueue
        
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: nil) { [weak self] buffer, _ in
            guard self != nil else { return }
            queue.async {
                callback?(buffer)
            }
        }

        engine.prepare()

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw AudioCaptureError.engineStartFailed(error)
        }

        audioEngine = engine
        isRecording = true
        Self.logger.info("Recording started")
    }

    public func stopRecording() {
        guard isRecording, let engine = audioEngine else { return }

        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        engine.reset()
        audioEngine = nil
        isRecording = false
        Self.logger.info("Recording stopped")
    }
}

public enum AudioCaptureError: Error, LocalizedError {
    case permissionDenied
    case noInputDevice
    case engineStartFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied"
        case .noInputDevice:
            return "No audio input device found"
        case .engineStartFailed(let error):
            return "Failed to start audio engine: \(error.localizedDescription)"
        }
    }
}
