import AppKit
import AVFoundation
import Foundation

/// Main controller orchestrating all CmdSpeak components.
/// Handles the flow: hotkey → audio → VAD → transcription → injection
@MainActor
public final class CmdSpeakController {
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
    private var listeningStartTime: Date?
    private let minListeningDuration: TimeInterval = 0.5

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
        print("[Controller] Setting up callbacks...")
        hotkeyManager.onHotkeyTriggered = { [weak self] in
            print("[Controller] onHotkeyTriggered closure entered")
            guard let self = self else {
                print("[Controller] self is nil!")
                return
            }
            print("[Controller] Scheduling on main run loop...")
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
                print("[Controller] Run loop block executing")
                Task { @MainActor in
                    print("[Controller] Task starting handleHotkeyTriggered")
                    await self.handleHotkeyTriggered()
                    print("[Controller] handleHotkeyTriggered completed")
                }
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
            print("[Controller] Run loop woken")
        }
        print("[Controller] Callbacks setup complete")

        vad.onSpeechEnd = { [weak self] in
            Task { @MainActor in
                await self?.handleSpeechEnd()
            }
        }

        audioCapture.onAudioBuffer = { [weak self] buffer in
            self?.handleAudioBuffer(buffer)
        }
    }

    public func start() async throws {
        print("[Controller] start() called, initializing engine...")
        try await engine.initialize()
        print("[Controller] Engine initialized")

        var attempts = 0
        while attempts < 60 {
            do {
                try hotkeyManager.start()
                print("[Controller] Hotkey manager started, setting state to idle")
                setState(.idle)
                print("[Controller] start() completing successfully")
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
        print("[Controller] handleHotkeyTriggered called, state: \(state)")
        switch state {
        case .idle:
            print("[Controller] Starting listening...")
            await startListening()
        case .listening:
            if let startTime = listeningStartTime {
                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed < minListeningDuration {
                    print("[Controller] Ignoring stop - only \(String(format: "%.2f", elapsed))s elapsed (min: \(minListeningDuration)s)")
                    return
                }
            }
            print("[Controller] Stopping listening...")
            await stopListening()
        default:
            print("[Controller] Ignoring hotkey in state: \(state)")
            break
        }
    }

    private func startListening() async {
        print("[Controller] startListening() called")
        setState(.listening)
        listeningStartTime = Date()
        clearBuffer()
        vad.reset()

        do {
            print("[Controller] Starting audio capture...")
            try await audioCapture.startRecording()
            print("[Controller] Audio capture started successfully")
            playFeedbackSound(start: true)
        } catch {
            print("[Controller] Audio capture error: \(error)")
            listeningStartTime = nil
            setState(.error(error.localizedDescription))
        }
    }

    private func stopListening() async {
        listeningStartTime = nil
        audioCapture.stopRecording()
        await processAndInject()
    }

    private var lastBufferLogTime: Date?
    
    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        let inputSampleRate = buffer.format.sampleRate
        let targetSampleRate = 16000.0

        var samplesAdded = 0
        if inputSampleRate != targetSampleRate && inputSampleRate > 0 {
            let ratio = inputSampleRate / targetSampleRate
            let outputLength = Int(Double(frameLength) / ratio)
            guard outputLength > 0 else { return }

            bufferQueue.sync {
                for i in 0..<outputLength {
                    let srcIndex = Int(Double(i) * ratio)
                    if srcIndex < frameLength {
                        audioBuffer.append(channelData[srcIndex])
                        samplesAdded += 1
                    }
                }
            }
        } else {
            bufferQueue.sync {
                for i in 0..<frameLength {
                    audioBuffer.append(channelData[i])
                    samplesAdded += 1
                }
            }
        }

        let now = Date()
        if lastBufferLogTime == nil || now.timeIntervalSince(lastBufferLogTime!) >= 0.5 {
            var totalSamples = 0
            bufferQueue.sync { totalSamples = audioBuffer.count }
            print("[Audio] Receiving... \(totalSamples) samples (\(String(format: "%.1f", Double(totalSamples) / 16000.0))s)")
            lastBufferLogTime = now
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

        let durationSec = Double(samples.count) / 16000.0
        print("\n[Audio] Captured \(samples.count) samples (\(String(format: "%.1f", durationSec))s)")

        guard !samples.isEmpty else {
            print("[Audio] No audio captured")
            setState(.idle)
            return
        }

        guard samples.count > 1600 else {
            print("[Audio] Too short, skipping")
            setState(.idle)
            return
        }

        do {
            print("[Transcribing...]")
            let result = try await engine.transcribe(audioSamples: samples)

            guard !result.text.isEmpty else {
                print("[Result] Empty transcription")
                setState(.idle)
                return
            }

            print("[Result] \"\(result.text)\"")
            setState(.injecting)
            try injector.inject(text: result.text)
            playFeedbackSound(start: false)
            setState(.idle)
        } catch {
            print("[Error] \(error.localizedDescription)")
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
