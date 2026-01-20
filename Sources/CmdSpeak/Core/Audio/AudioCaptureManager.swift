import AVFoundation
import Foundation

/// Protocol for audio capture functionality.
public protocol AudioCapturing: AnyObject {
    var isRecording: Bool { get }
    var onAudioBuffer: ((_ buffer: AVAudioPCMBuffer) -> Void)? { get set }

    func startRecording() async throws
    func stopRecording()
    func requestPermission() async -> Bool
}

/// Manages microphone audio capture using AVAudioEngine.
/// Captures 16kHz mono Float32 audio suitable for Whisper transcription.
public final class AudioCaptureManager: AudioCapturing, @unchecked Sendable {
    private let audioEngine = AVAudioEngine()
    private var isSetup = false

    public private(set) var isRecording = false
    public var onAudioBuffer: ((_ buffer: AVAudioPCMBuffer) -> Void)?

    /// Target format for Whisper: 16kHz mono Float32
    private let targetSampleRate: Double = 16000
    private let targetChannelCount: AVAudioChannelCount = 1

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

        try setupAudioEngine()

        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            throw AudioCaptureError.engineStartFailed(error)
        }
    }

    public func stopRecording() {
        guard isRecording else { return }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRecording = false
    }

    private func setupAudioEngine() throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0 else {
            throw AudioCaptureError.noInputDevice
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: targetChannelCount,
            interleaved: false
        ) else {
            throw AudioCaptureError.formatCreationFailed
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioCaptureError.converterCreationFailed
        }

        let bufferSize: AVAudioFrameCount = 4096

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) {
            [weak self] buffer, _ in
            self?.processBuffer(buffer, converter: converter, targetFormat: targetFormat)
        }

        isSetup = true
    }

    private func processBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCapacity
        ) else { return }

        var error: NSError?
        var inputConsumed = false

        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if error == nil, outputBuffer.frameLength > 0 {
            onAudioBuffer?(outputBuffer)
        }
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
