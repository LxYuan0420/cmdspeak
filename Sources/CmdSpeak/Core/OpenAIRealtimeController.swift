import AppKit
import AVFoundation
import Foundation
import os

/// Controller for OpenAI Realtime API transcription mode.
/// Provides streaming transcription with server-side VAD.
@MainActor
public final class OpenAIRealtimeController {
    private static let logger = Logger(subsystem: "com.cmdspeak", category: "realtime-controller")

    public enum State: Sendable {
        case idle
        case connecting
        case listening
        case processing
        case error(String)
    }

    public private(set) var state: State = .idle
    public var onStateChange: ((State) -> Void)?
    public var onPartialTranscription: ((String) -> Void)?
    public var onFinalTranscription: ((String) -> Void)?

    private let config: Config
    private let audioCapture: AudioCaptureManager
    private let engine: OpenAIRealtimeEngine
    private let injector: TextInjector
    private let hotkeyManager: HotkeyManager

    private var isConnected: Bool = false
    private let maxListeningDuration: TimeInterval = 60.0
    private var maxDurationTimer: Timer?
    private var silenceTimer: Timer?
    private let silenceTimeout: TimeInterval = 1.5
    private var lastTranscriptionTime: Date?

    private let inputSampleRate: Double = 24000

    public init(config: Config) {
        self.config = config

        let apiKey = Self.resolveEnvValue(config.model.apiKey ?? "env:OPENAI_API_KEY")
        self.engine = OpenAIRealtimeEngine(
            apiKey: apiKey,
            model: config.model.name.isEmpty ? "gpt-4o-transcribe" : config.model.name,
            language: config.model.language
        )
        self.audioCapture = AudioCaptureManager()
        self.injector = TextInjector()
        self.hotkeyManager = HotkeyManager(
            doubleTapInterval: TimeInterval(config.hotkey.intervalMs) / 1000.0
        )

        setupCallbacks()
    }

    private static func resolveEnvValue(_ value: String) -> String {
        if value.hasPrefix("env:") {
            let envName = String(value.dropFirst(4))
            return ProcessInfo.processInfo.environment[envName] ?? ""
        }
        return value
    }

    private func setupCallbacks() {
        hotkeyManager.onHotkeyTriggered = { [weak self] in
            DispatchQueue.main.async {
                Task { @MainActor in
                    await self?.handleHotkeyTriggered()
                }
            }
        }

        audioCapture.onAudioBuffer = { [weak self] buffer in
            self?.handleAudioBuffer(buffer)
        }

        Task {
            await engine.setPartialTranscriptionHandler { [weak self] delta in
                Task { @MainActor in
                    self?.handlePartialTranscription(delta)
                }
            }
        }
    }

    private func handlePartialTranscription(_ delta: String) {
        onPartialTranscription?(delta)
        lastTranscriptionTime = Date()
        resetSilenceTimer()
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(
            withTimeInterval: silenceTimeout,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, case .listening = self.state else { return }
                await self.finishListening()
            }
        }
    }

    public func start() async throws {
        Self.logger.info("Initializing OpenAI Realtime Engine")
        try await engine.initialize()
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
        cancelTimers()
        audioCapture.stopRecording()
        hotkeyManager.stop()
        Task {
            await engine.disconnect()
        }
        setState(.idle)
    }

    private func handleHotkeyTriggered() async {
        switch state {
        case .idle:
            await startListening()
        case .listening, .processing:
            await cancelListening()
        default:
            break
        }
    }

    private func cancelTimers() {
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
    }

    private func cancelListening() async {
        cancelTimers()
        audioCapture.stopRecording()
        await engine.disconnect()
        isConnected = false
        setState(.idle)
    }

    private func startListening() async {
        setState(.connecting)

        do {
            try await engine.connect()
            isConnected = true

            try await audioCapture.startRecording()
            playFeedbackSound(start: true)
            startMaxDurationTimer()
            setState(.listening)
            lastTranscriptionTime = nil

            await engine.clearTranscription()
        } catch {
            setState(.error(error.localizedDescription))
        }
    }

    private func finishListening() async {
        cancelTimers()
        audioCapture.stopRecording()

        let transcription = await engine.getTranscription()
        await engine.disconnect()
        isConnected = false

        if !transcription.isEmpty {
            onFinalTranscription?(transcription)
            do {
                try injector.inject(text: transcription)
            } catch {
                setState(.error("Failed to inject text"))
                return
            }
        }

        playFeedbackSound(start: false)
        setState(.idle)
    }

    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isConnected, case .listening = state else { return }
        guard let channelData = buffer.floatChannelData?[0] else { return }

        let frameLength = Int(buffer.frameLength)
        let sourceSampleRate = buffer.format.sampleRate

        let targetLength = Int(Double(frameLength) * inputSampleRate / sourceSampleRate)
        guard targetLength > 0 else { return }

        var resampled = [Float](repeating: 0, count: targetLength)
        let ratio = sourceSampleRate / inputSampleRate

        for i in 0..<targetLength {
            let srcIndex = Int(Double(i) * ratio)
            if srcIndex < frameLength {
                resampled[i] = channelData[srcIndex]
            }
        }

        Task {
            try? await engine.sendAudio(samples: resampled)
        }
    }

    private func startMaxDurationTimer() {
        maxDurationTimer?.invalidate()
        maxDurationTimer = Timer.scheduledTimer(
            withTimeInterval: maxListeningDuration,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, case .listening = self.state else { return }
                await self.finishListening()
            }
        }
    }

    private func setState(_ newState: State) {
        state = newState
        onStateChange?(newState)
    }

    private func playFeedbackSound(start: Bool) {
        guard config.feedback.soundEnabled else { return }
        let sound: NSSound? = start ? NSSound(named: "Tink") : NSSound(named: "Pop")
        sound?.play()
    }
}
