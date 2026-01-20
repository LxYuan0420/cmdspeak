import AVFoundation
import Foundation

public protocol AudioCapturing: AnyObject {
    var isRecording: Bool { get }
    var onAudioBuffer: ((_ buffer: AVAudioPCMBuffer) -> Void)? { get set }

    func startRecording() async throws
    func stopRecording()
    func requestPermission() async -> Bool
}

public final class AudioCaptureManager: AudioCapturing, @unchecked Sendable {
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

        guard format.sampleRate > 0 else {
            throw AudioCaptureError.noInputDevice
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.onAudioBuffer?(buffer)
        }

        engine.prepare()
        try engine.start()

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
