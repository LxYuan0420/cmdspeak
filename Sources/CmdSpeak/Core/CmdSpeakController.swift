import AppKit
import AVFoundation
import Foundation
import os

/// Main controller orchestrating all CmdSpeak components.
/// Handles the flow: hotkey → audio → VAD → transcription → injection
@MainActor
public final class CmdSpeakController {
    private static let logger = Logger(subsystem: "com.cmdspeak", category: "controller")

    public enum State: Sendable {
        case idle
        case listening
        case processing
        case injecting
        case error(String)
    }

    public private(set) var state: State = .idle
    public var onStateChange: ((State) -> Void)?
    public var onModelLoadProgress: ((ModelLoadProgress) -> Void)?

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
    private let maxListeningDuration: TimeInterval = 60.0
    private var maxDurationTimer: Timer?

    public init(config: Config = Config.default) {
        self.config = config
        self.audioCapture = AudioCaptureManager()
        self.vad = VoiceActivityDetector(
            silenceDuration: TimeInterval(config.audio.silenceThresholdMs) / 1000.0
        )
        self.engine = WhisperKitEngine(modelName: config.model.name, language: config.model.language, translateToEnglish: config.model.translateToEnglish)
        self.injector = TextInjector()
        self.hotkeyManager = HotkeyManager(
            doubleTapInterval: TimeInterval(config.hotkey.intervalMs) / 1000.0
        )

        setupCallbacks()
    }

    private func setupCallbacks() {
        Self.logger.debug("Setting up callbacks")
        hotkeyManager.onHotkeyTriggered = { [weak self] in
            Task { @MainActor in
                await self?.handleHotkeyTriggered()
            }
        }
        Self.logger.debug("Callbacks setup complete")

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
        Self.logger.info("Initializing engine")
        let progressCallback = onModelLoadProgress
        try await engine.initialize { progress in
            Task { @MainActor in
                progressCallback?(progress)
            }
        }
        Self.logger.info("Engine initialized")

        var attempts = 0
        while attempts < 60 {
            do {
                try hotkeyManager.start()
                Self.logger.info("Hotkey manager started")
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
        cancelMaxDurationTimer()
        audioCapture.stopRecording()
        hotkeyManager.stop()
        Task {
            await engine.unload()
        }
        setState(.idle)
    }

    private func handleHotkeyTriggered() async {
        Self.logger.debug("Hotkey triggered, state: \(String(describing: self.state))")
        switch state {
        case .idle:
            Self.logger.info("Starting listening")
            await startListening()
        case .listening:
            if let startTime = listeningStartTime {
                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed < minListeningDuration {
                    Self.logger.debug("Ignoring stop - only \(String(format: "%.2f", elapsed))s elapsed")
                    return
                }
            }
            Self.logger.info("Stopping listening")
            await stopListening()
        default:
            Self.logger.debug("Ignoring hotkey in state: \(String(describing: self.state))")
            break
        }
    }

    private func startListening() async {
        setState(.listening)
        listeningStartTime = Date()
        clearBuffer()
        vad.reset()

        do {
            try await audioCapture.startRecording()
            Self.logger.info("Audio capture started")
            playFeedbackSound(start: true)
            startMaxDurationTimer()
        } catch {
            Self.logger.error("Audio capture failed: \(error.localizedDescription)")
            listeningStartTime = nil
            setState(.error(error.localizedDescription))
        }
    }

    private func stopListening() async {
        cancelMaxDurationTimer()
        listeningStartTime = nil
        audioCapture.stopRecording()
        await processAndInject()
    }

    private func startMaxDurationTimer() {
        cancelMaxDurationTimer()
        maxDurationTimer = Timer.scheduledTimer(withTimeInterval: maxListeningDuration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, case .listening = self.state else { return }
                Self.logger.info("Max duration reached, stopping")
                await self.stopListening()
            }
        }
    }

    private func cancelMaxDurationTimer() {
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil
    }

    private var lastBufferLogTime: Date?
    
    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        let inputSampleRate = buffer.format.sampleRate
        let targetSampleRate = 16000.0

        if inputSampleRate != targetSampleRate && inputSampleRate > 0 {
            let ratio = inputSampleRate / targetSampleRate
            let outputLength = Int(Double(frameLength) / ratio)
            guard outputLength > 0 else { return }

            bufferQueue.sync {
                for i in 0..<outputLength {
                    let srcIndex = Int(Double(i) * ratio)
                    if srcIndex < frameLength {
                        audioBuffer.append(channelData[srcIndex])
                    }
                }
            }
        } else {
            bufferQueue.sync {
                for i in 0..<frameLength {
                    audioBuffer.append(channelData[i])
                }
            }
        }

        let now = Date()
        if lastBufferLogTime.map({ now.timeIntervalSince($0) >= 0.5 }) ?? true {
            var totalSamples = 0
            bufferQueue.sync { totalSamples = audioBuffer.count }
            Self.logger.debug("Audio buffer: \(totalSamples) samples (\(String(format: "%.1f", Double(totalSamples) / 16000.0))s)")
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
        Self.logger.info("Captured \(samples.count) samples (\(String(format: "%.1f", durationSec))s)")

        guard !samples.isEmpty else {
            Self.logger.debug("No audio captured")
            setState(.idle)
            return
        }

        guard samples.count > 1600 else {
            Self.logger.debug("Audio too short, skipping")
            setState(.idle)
            return
        }

        do {
            Self.logger.info("Transcribing")
            let result = try await engine.transcribe(audioSamples: samples)

            guard !result.text.isEmpty else {
                Self.logger.debug("Empty transcription")
                setState(.idle)
                return
            }

            Self.logger.info("Result: \"\(result.text)\"")
            setState(.injecting)
            try injector.inject(text: result.text)
            playFeedbackSound(start: false)
            setState(.idle)
        } catch {
            Self.logger.error("Transcription failed: \(error.localizedDescription)")
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
