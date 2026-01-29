import AVFoundation
import Foundation
import os

/// Captures audio from the default input device using AVAudioEngine.
/// Provides audio buffers via callback for transcription.
@MainActor
public final class AudioCaptureManager {
    private static let logger = Logger(subsystem: "com.cmdspeak", category: "audio-capture")

    private var audioEngine: AVAudioEngine?
    private let bufferSize: AVAudioFrameCount = 4096

    public private(set) var isRecording = false
    public var onAudioBuffer: ((_ buffer: AVAudioPCMBuffer) -> Void)?

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

        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw AudioCaptureError.noInputDevice
        }

        Self.logger.info("Audio input: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")

        let callback = onAudioBuffer
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard self != nil else { return }
            Task { @MainActor in
                callback?(buffer)
            }
        }

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

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioEngine = nil
        isRecording = false
        Self.logger.info("Recording stopped")
    }
}

public enum AudioCaptureError: Error, LocalizedError {
    case permissionDenied
    case noInputDevice
    case formatCreationFailed
    case converterCreationFailed
    case engineStartFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied"
        case .noInputDevice:
            return "No audio input device found"
        case .formatCreationFailed:
            return "Failed to create audio format"
        case .converterCreationFailed:
            return "Failed to create audio converter"
        case .engineStartFailed(let error):
            return "Failed to start audio engine: \(error.localizedDescription)"
        }
    }
}
