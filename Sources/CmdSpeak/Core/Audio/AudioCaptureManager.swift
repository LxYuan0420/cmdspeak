import AVFoundation
import Foundation

@MainActor
public final class AudioCaptureManager {
    private var audioEngine: AVAudioEngine?

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
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioCaptureError.noInputDevice
        }

        let callback = onAudioBuffer
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            callback?(buffer)
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
    }

    public func stopRecording() {
        guard isRecording, let engine = audioEngine else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioEngine = nil
        isRecording = false
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
