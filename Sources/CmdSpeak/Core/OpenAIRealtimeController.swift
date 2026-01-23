import AppKit
import AVFoundation
import Foundation
import os

/// Controller for OpenAI Realtime API transcription mode.
/// Provides streaming transcription with server-side VAD.
@MainActor
public final class OpenAIRealtimeController {
    private static let logger = Logger(subsystem: "com.cmdspeak", category: "realtime-controller")

    public enum State: Sendable, Equatable {
        case idle
        case connecting
        case listening
        case finalizing
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

    private var silenceTimer: Timer?
    private let silenceTimeout: TimeInterval
    private var pendingText: String = ""

    private var currentSessionID: UUID?
    private var audioSendTask: Task<Void, Never>?
    private var audioBufferContinuation: AsyncStream<[Float]>.Continuation?

    private static let maxReconnectAttempts = 3
    private static let reconnectBaseDelay: TimeInterval = 0.5
    private static let finalTranscriptTimeout: TimeInterval = 3.0
    private static let maxAudioBufferQueue = 50

    private let inputSampleRate: Double = 24000
    private var droppedBufferCount = 0

    public init(config: Config) {
        self.config = config
        self.silenceTimeout = TimeInterval(config.audio.silenceThresholdMs) / 1000.0

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

            await engine.setOnDisconnect { [weak self] wasIntentional in
                Task { @MainActor in
                    await self?.handleUnexpectedDisconnect(wasIntentional: wasIntentional)
                }
            }

            await engine.setOnError { [weak self] message in
                Task { @MainActor in
                    self?.handleEngineError(message)
                }
            }
        }
    }

    private func handlePartialTranscription(_ delta: String) {
        guard case .listening = state else { return }
        pendingText += delta
        onPartialTranscription?(delta)
        resetSilenceTimer()
    }

    private func handleUnexpectedDisconnect(wasIntentional: Bool) async {
        guard !wasIntentional, case .listening = state else { return }

        Self.logger.warning("Unexpected disconnect during listening")
        audioCapture.stopRecording()
        silenceTimer?.invalidate()
        silenceTimer = nil

        let savedSessionID = currentSessionID
        let savedText = pendingText

        for attempt in 1...Self.maxReconnectAttempts {
            guard currentSessionID == savedSessionID else {
                Self.logger.info("Session changed, aborting reconnect")
                return
            }

            let delay = Self.reconnectBaseDelay * pow(2.0, Double(attempt - 1))
            let jitter = Double.random(in: 0...0.3)
            Self.logger.info("Reconnect attempt \(attempt)/\(Self.maxReconnectAttempts) in \(delay + jitter)s")

            try? await Task.sleep(nanoseconds: UInt64((delay + jitter) * 1_000_000_000))

            guard currentSessionID == savedSessionID else { return }

            do {
                try await engine.connect()
                try await audioCapture.startRecording()
                pendingText = savedText
                resetSilenceTimer()
                Self.logger.info("Reconnected successfully")
                return
            } catch {
                Self.logger.error("Reconnect attempt \(attempt) failed: \(error.localizedDescription)")
            }
        }

        Self.logger.error("All reconnect attempts failed")
        await finishAndInject()
    }

    private func handleEngineError(_ message: String) {
        if message.contains("invalid_api_key") || message.contains("authentication") {
            Self.logger.error("Authentication error - not retrying")
            setState(.error("Invalid API key"))
        }
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(
            withTimeInterval: silenceTimeout,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, case .listening = self.state else { return }
                await self.finishAndInject()
            }
        }
    }

    private func finishAndInject() async {
        let sessionID = currentSessionID
        guard case .listening = state else { return }

        setState(.finalizing)
        silenceTimer?.invalidate()
        silenceTimer = nil
        audioCapture.stopRecording()
        stopAudioSendPipeline()

        do {
            try await engine.commitAudio()
        } catch {
            Self.logger.warning("Failed to commit audio: \(error.localizedDescription)")
        }

        let finalText = await engine.awaitFinalTranscript(timeout: Self.finalTranscriptTimeout)
        await engine.disconnect()

        guard currentSessionID == sessionID else {
            Self.logger.info("Session changed during finalization, discarding")
            return
        }

        let text = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingText = ""
        currentSessionID = nil

        if !text.isEmpty {
            onFinalTranscription?(text)
            do {
                try injector.inject(text: text)
                playFeedbackSound(start: false)
            } catch {
                setState(.error("Failed to inject text"))
                return
            }
        }
        setState(.idle)
    }

    public func start() async throws {
        try validateConfig()

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

    private func validateConfig() throws {
        let apiKey = Self.resolveEnvValue(config.model.apiKey ?? "env:OPENAI_API_KEY")
        guard !apiKey.isEmpty else {
            throw ConfigurationError.missingAPIKey
        }

        guard config.audio.silenceThresholdMs >= 1000 && config.audio.silenceThresholdMs <= 60000 else {
            throw ConfigurationError.invalidSilenceThreshold(config.audio.silenceThresholdMs)
        }

        guard config.hotkey.intervalMs >= 100 && config.hotkey.intervalMs <= 1000 else {
            throw ConfigurationError.invalidHotkeyInterval(config.hotkey.intervalMs)
        }
    }

    public func stop() {
        currentSessionID = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
        audioCapture.stopRecording()
        stopAudioSendPipeline()
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
        case .listening:
            await finishAndInject()
        case .connecting, .finalizing:
            break
        case .error:
            setState(.idle)
        }
    }

    private func startListening() async {
        let sessionID = UUID()
        currentSessionID = sessionID

        setState(.connecting)
        pendingText = ""
        droppedBufferCount = 0

        do {
            try await engine.connect()

            guard currentSessionID == sessionID else {
                Self.logger.info("Session cancelled before recording started")
                await engine.disconnect()
                return
            }

            startAudioSendPipeline()
            try await audioCapture.startRecording()
            playFeedbackSound(start: true)
            setState(.listening)

            await engine.clearTranscription()
            resetSilenceTimer()
        } catch {
            if currentSessionID == sessionID {
                Self.logger.error("Failed to start listening: \(error.localizedDescription)")
                stopAudioSendPipeline()
                setState(.error(error.localizedDescription))
                currentSessionID = nil
            }
        }
    }

    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard case .listening = state, currentSessionID != nil else { return }
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

        if let continuation = audioBufferContinuation {
            continuation.yield(resampled)
        }
    }

    private func startAudioSendPipeline() {
        let (stream, continuation) = AsyncStream<[Float]>.makeStream(bufferingPolicy: .bufferingNewest(Self.maxAudioBufferQueue))
        audioBufferContinuation = continuation

        audioSendTask = Task { [weak self] in
            for await samples in stream {
                guard let self = self, !Task.isCancelled else { break }
                do {
                    try await self.engine.sendAudio(samples: samples)
                } catch {
                    Self.logger.warning("Failed to send audio: \(error.localizedDescription)")
                }
            }
        }
    }

    private func stopAudioSendPipeline() {
        audioBufferContinuation?.finish()
        audioBufferContinuation = nil
        audioSendTask?.cancel()
        audioSendTask = nil
        if droppedBufferCount > 0 {
            let dropped = droppedBufferCount
            Self.logger.warning("Dropped \(dropped) audio buffers this session")
            droppedBufferCount = 0
        }
    }

    private func setState(_ newState: State) {
        guard state != newState else { return }
        Self.logger.info("State: \(String(describing: self.state)) → \(String(describing: newState))")
        state = newState
        onStateChange?(newState)
    }

    private func playFeedbackSound(start: Bool) {
        guard config.feedback.soundEnabled else { return }
        let sound: NSSound? = start ? NSSound(named: "Tink") : NSSound(named: "Pop")
        sound?.play()
    }
}

public enum ConfigurationError: Error, LocalizedError {
    case missingAPIKey
    case invalidSilenceThreshold(Int)
    case invalidHotkeyInterval(Int)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OPENAI_API_KEY is not set"
        case .invalidSilenceThreshold(let ms):
            return "Silence threshold \(ms)ms is out of range (1000-60000ms)"
        case .invalidHotkeyInterval(let ms):
            return "Hotkey interval \(ms)ms is out of range (100-1000ms)"
        }
    }
}
