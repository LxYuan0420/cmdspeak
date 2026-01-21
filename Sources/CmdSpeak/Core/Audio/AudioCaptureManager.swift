import AVFoundation
import Foundation

@MainActor
public final class AudioCaptureManager: NSObject {
    private var captureSession: AVCaptureSession?
    private var audioOutput: AVCaptureAudioDataOutput?
    private let processingQueue = DispatchQueue(label: "com.cmdspeak.audio", qos: .userInteractive)

    public private(set) var isRecording = false
    public var onAudioBuffer: ((_ buffer: AVAudioPCMBuffer) -> Void)?

    public override init() {
        super.init()
    }

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

        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw AudioCaptureError.noInputDevice
        }

        let session = AVCaptureSession()
        session.sessionPreset = .high

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw AudioCaptureError.noInputDevice
        }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: processingQueue)

        guard session.canAddOutput(output) else {
            throw AudioCaptureError.noInputDevice
        }
        session.addOutput(output)

        captureSession = session
        audioOutput = output

        session.startRunning()
        isRecording = true
    }

    public func stopRecording() {
        guard isRecording, let session = captureSession else { return }

        session.stopRunning()
        captureSession = nil
        audioOutput = nil
        isRecording = false
    }
}

extension AudioCaptureManager: AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return
        }

        let sampleRate = asbd.pointee.mSampleRate
        let channels = asbd.pointee.mChannelsPerFrame
        let formatID = asbd.pointee.mFormatID
        let bitsPerChannel = asbd.pointee.mBitsPerChannel
        let formatFlags = asbd.pointee.mFormatFlags

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return
        }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )

        guard status == kCMBlockBufferNoErr, let data = dataPointer, length > 0 else {
            return
        }

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channels),
            interleaved: false
        ) else {
            return
        }

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else {
            return
        }
        outputBuffer.frameLength = AVAudioFrameCount(frameCount)

        guard let channelData = outputBuffer.floatChannelData else {
            return
        }

        let isFloat = (formatFlags & kAudioFormatFlagIsFloat) != 0
        let isSignedInt = (formatFlags & kAudioFormatFlagIsSignedInteger) != 0

        if formatID == kAudioFormatLinearPCM {
            if isFloat && bitsPerChannel == 32 {
                let floatData = UnsafeRawPointer(data).bindMemory(to: Float.self, capacity: frameCount * Int(channels))
                for frame in 0..<frameCount {
                    for channel in 0..<Int(channels) {
                        let srcIndex = frame * Int(channels) + channel
                        channelData[channel][frame] = floatData[srcIndex]
                    }
                }
            } else if isSignedInt && bitsPerChannel == 16 {
                let int16Data = UnsafeRawPointer(data).bindMemory(to: Int16.self, capacity: frameCount * Int(channels))
                for frame in 0..<frameCount {
                    for channel in 0..<Int(channels) {
                        let srcIndex = frame * Int(channels) + channel
                        channelData[channel][frame] = Float(int16Data[srcIndex]) / Float(Int16.max)
                    }
                }
            } else if isSignedInt && bitsPerChannel == 32 {
                let int32Data = UnsafeRawPointer(data).bindMemory(to: Int32.self, capacity: frameCount * Int(channels))
                for frame in 0..<frameCount {
                    for channel in 0..<Int(channels) {
                        let srcIndex = frame * Int(channels) + channel
                        channelData[channel][frame] = Float(int32Data[srcIndex]) / Float(Int32.max)
                    }
                }
            } else {
                return
            }
        } else {
            return
        }

        Task { @MainActor [weak self] in
            self?.onAudioBuffer?(outputBuffer)
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
