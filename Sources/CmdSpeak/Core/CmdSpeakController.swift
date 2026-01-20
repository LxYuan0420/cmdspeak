import AppKit
import AVFoundation
import Foundation

/// Main controller orchestrating all CmdSpeak components.
/// Handles the flow: hotkey → audio → VAD → transcription → injection
public final class CmdSpeakController: @unchecked Sendable {
    public enum State: Sendable {
        case idle
        case listening
        case processing
        case injecting
        case error(String)
    }

    public private(set) var state: State = .idle
    public var onStateChange: ((State) -> Void)?

    private let config: Config
    private let audioCapture: AudioCaptureManager
    private let vad: VoiceActivityDetector
    private let engine: WhisperKitEngine
    private let injector: TextInjector
    private let hotkeyManager: HotkeyManager

    private var audioBuffer: [Float] = []
    private let bufferQueue = DispatchQueue(label: "com.cmdspeak.buffer", qos: .userInteractive)

    public init(config: Config = Config.default) {
        self.config = config
        self.audioCapture = AudioCaptureManager()
        self.vad = VoiceActivityDetector(
            silenceDuration: TimeInterval(config.audio.silenceThresholdMs) / 1000.0
        )
        self.engine = WhisperKitEngine(modelName: config.model.name)
        self.injector = TextInjector()
        self.hotkeyManager = HotkeyManager(
            doubleTapInterval: TimeInterval(config.hotkey.intervalMs) / 1000.0
        )

        setupCallbacks()
    }

    private func setupCallbacks() {
        hotkeyManager.onHotkeyTriggered = { [weak self] in
            Task { @MainActor in
                await self?.handleHotkeyTriggered()
            }
        }

        vad.onSpeechEnd = { [weak self] in
            Task {
                await self?.handleSpeechEnd()
            }
        }

        audioCapture.onAudioBuffer = { [weak self] buffer in
            self?.handleAudioBuffer(buffer)
        }
    }

    public func start() async throws {
        try await engine.initialize()

        // Wait for accessibility permission with retries
        var attempts = 0
        while attempts < 60 {
            do {
                try hotkeyManager.start()
                setState(.idle)
                return
            } catch HotkeyError.accessibilityNotGranted {
                attempts += 1
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        throw HotkeyError.accessibilityNotGranted
    }

    public func stop() {
        audioCapture.stopRecording()
        hotkeyManager.stop()
        Task {
            await engine.unload()
        }
        setState(.idle)
    }

    private func handleHotkeyTriggered() async {
        switch state {
        case .idle:
            await startListening()
        case .listening:
            await stopListening()
        default:
            break
        }
    }

    private func startListening() async {
        setState(.listening)
        clearBuffer()
        vad.reset()

        do {
            try await audioCapture.startRecording()
            playFeedbackSound(start: true)
        } catch {
            setState(.error(error.localizedDescription))
        }
    }

    private func stopListening() async {
        audioCapture.stopRecording()
        await processAndInject()
    }

    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)

        bufferQueue.sync {
            for i in 0..<frameLength {
                audioBuffer.append(channelData[i])
            }
        }

        vad.process(buffer: buffer)
    }

    private func handleSpeechEnd() async {
        guard case .listening = state else { return }
        audioCapture.stopRecording()
        await processAndInject()
    }

    private func processAndInject() async {
        setState(.processing)

        var samples: [Float] = []
        bufferQueue.sync {
            samples = audioBuffer
        }

        guard !samples.isEmpty else {
            setState(.idle)
            return
        }

        do {
            let result = try await engine.transcribe(audioSamples: samples)

            guard !result.text.isEmpty else {
                setState(.idle)
                return
            }

            setState(.injecting)
            try injector.inject(text: result.text)
            playFeedbackSound(start: false)
            setState(.idle)
        } catch {
            setState(.error(error.localizedDescription))
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.setState(.idle)
            }
        }
    }

    private func clearBuffer() {
        bufferQueue.sync {
            audioBuffer.removeAll()
        }
    }

    private func setState(_ newState: State) {
        state = newState
        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?(newState)
        }
    }

    private func playFeedbackSound(start: Bool) {
        guard config.feedback.soundEnabled else { return }

        let sound: NSSound? = start
            ? NSSound(named: "Tink")
            : NSSound(named: "Pop")
        sound?.play()
    }
}
