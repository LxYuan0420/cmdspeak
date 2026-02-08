import AppKit
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
        case reconnecting(attempt: Int, maxAttempts: Int)
        case finalizing
        case error(String)
    }

    public private(set) var state: State = .idle
    public var onStateChange: ((State) -> Void)?
    public var onPartialTranscription: ((String) -> Void)?
    public var onFinalTranscription: ((String) -> Void)?
    public var onSessionMetrics: ((SessionMetrics) -> Void)?

    private let config: Config
    private let audioCapture: AudioCaptureManager
    private let engine: OpenAIRealtimeEngine
    private let injector: TextInjector
    private let hotkeyManager: HotkeyManager

    private var silenceTimer: Timer?
    private let silenceTimeout: TimeInterval
    private var isSpeaking: Bool = false

    private var currentSessionID: UUID?
    private var audioSendTask: Task<Void, Never>?
    private var audioBufferContinuation: AsyncStream<[Float]>.Continuation?

    private static let maxReconnectAttempts = 3
    private static let reconnectBaseDelay: TimeInterval = 0.5
    private static let finalTranscriptTimeout: TimeInterval = 3.0
    private static let maxAudioBufferQueue = 50

    private var droppedBufferCount = 0
    private var forceInjectRequested = false
    private var metricsCollector: SessionMetricsCollector?

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
            Task { @MainActor in
                await self?.handleHotkeyTriggered()
            }
        }

        audioCapture.onAudioSamples = { [weak self] samples in
            DispatchQueue.main.async {
                self?.handleAudioSamples(samples)
            }
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

            await engine.setOnSpeechStarted { [weak self] in
                Task { @MainActor in
                    self?.handleSpeechStarted()
                }
            }

            await engine.setOnSpeechStopped { [weak self] in
                Task { @MainActor in
                    self?.handleSpeechStopped()
                }
            }
        }
    }

    private func handleSpeechStarted() {
        guard case .listening = state else { return }
        isSpeaking = true
        silenceTimer?.invalidate()
        silenceTimer = nil
        Self.logger.debug("VAD: speech started")
    }

    private func handleSpeechStopped() {
        guard case .listening = state else { return }
        isSpeaking = false
        Self.logger.debug("VAD: speech stopped, starting silence timer")
        resetSilenceTimer()
    }

    private func handlePartialTranscription(_ delta: String) {
        guard case .listening = state else { return }
        metricsCollector?.recordTranscription(characters: delta.count)
        onPartialTranscription?(delta)
    }

    private func handleUnexpectedDisconnect(wasIntentional: Bool) async {
        guard !wasIntentional, case .listening = state else { return }

        Self.logger.warning("Unexpected disconnect during listening")
        audioCapture.stopRecording()
        silenceTimer?.invalidate()
        silenceTimer = nil
        stopAudioSendPipeline()

        guard shouldRetryOnError else {
            Self.logger.info("Not retrying due to fatal error")
            metricsCollector?.recordDisconnect(reason: .connectionLost)
            await finishAndInject(reason: .connectionLost)
            return
        }

        let savedSessionID = currentSessionID

        for attempt in 1...Self.maxReconnectAttempts {
            guard currentSessionID == savedSessionID else {
                Self.logger.info("Session changed, aborting reconnect")
                return
            }

            guard shouldRetryOnError else {
                Self.logger.info("Fatal error received, stopping retries")
                break
            }

            metricsCollector?.recordReconnectAttempt()
            setState(.reconnecting(attempt: attempt, maxAttempts: Self.maxReconnectAttempts))

            let delay = Self.reconnectBaseDelay * pow(2.0, Double(attempt - 1))
            let jitter = Double.random(in: 0...0.3)
            Self.logger.info("Reconnect attempt \(attempt)/\(Self.maxReconnectAttempts) in \(delay + jitter)s")

            try? await Task.sleep(nanoseconds: UInt64((delay + jitter) * 1_000_000_000))

            guard currentSessionID == savedSessionID else { return }

            do {
                metricsCollector?.recordConnectionStart()
                try await engine.connect()
                metricsCollector?.recordConnectionEstablished()
                metricsCollector?.recordReconnectSuccess()
                startAudioSendPipeline()
                try await audioCapture.startRecording()
                setState(.listening)
                resetSilenceTimer()
                Self.logger.info("Reconnected successfully")
                return
            } catch {
                Self.logger.error("Reconnect attempt \(attempt) failed: \(error.localizedDescription)")
            }
        }

        Self.logger.error("All reconnect attempts failed")
        metricsCollector?.recordDisconnect(reason: .reconnectFailed)
        await finishAndInject(reason: .reconnectFailed)
    }

    private var shouldRetryOnError: Bool = true

    private func handleEngineError(_ error: RealtimeAPIError) {
        let errorType = classifyError(error)

        switch errorType {
        case .fatal(let userMessage):
            Self.logger.error("Fatal error: \(error.message)")
            shouldRetryOnError = false
            setState(.error(userMessage))
        case .transient:
            Self.logger.warning("Transient error: \(error.message)")
        }
    }

    private enum ErrorType {
        case fatal(String)
        case transient
    }

    private func classifyError(_ error: RealtimeAPIError) -> ErrorType {
        if let code = error.code {
            switch code {
            case "invalid_api_key", "authentication_error", "unauthorized":
                return .fatal("Invalid API key")
            case "model_not_found":
                return .fatal("Model not available")
            case "insufficient_quota", "billing_error":
                return .fatal("API quota exceeded")
            default:
                break
            }
        }

        let lowerMessage = error.message.lowercased()
        if lowerMessage.contains("invalid api key") ||
           lowerMessage.contains("authentication") ||
           lowerMessage.contains("unauthorized") {
            return .fatal("Invalid API key")
        }

        if lowerMessage.contains("model not found") {
            return .fatal("Model not available")
        }

        if lowerMessage.contains("billing") {
            return .fatal("API quota exceeded")
        }

        return .transient
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(
            withTimeInterval: silenceTimeout,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, case .listening = self.state else { return }
                self.metricsCollector?.recordDisconnect(reason: .silenceTimeout)
                await self.finishAndInject(reason: .silenceTimeout)
            }
        }
    }

    private func finishAndInject(reason: DisconnectReason = .userInitiated) async {
        let sessionID = currentSessionID
        guard case .listening = state else { return }

        setState(.finalizing)
        silenceTimer?.invalidate()
        silenceTimer = nil
        audioCapture.stopRecording()
        stopAudioSendPipeline()
        forceInjectRequested = false

        do {
            try await engine.commitAudio()
        } catch {
            Self.logger.warning("Failed to commit audio: \(error.localizedDescription)")
        }

        let finalText = await awaitFinalTranscriptWithForceCheck(timeout: Self.finalTranscriptTimeout)
        await engine.disconnect()

        guard currentSessionID == sessionID else {
            Self.logger.info("Session changed during finalization, discarding")
            finalizeMetrics(reason: .cancelled)
            return
        }

        let text = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        currentSessionID = nil
        forceInjectRequested = false

        finalizeMetrics(reason: reason)

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

    private func finalizeMetrics(reason: DisconnectReason) {
        guard let collector = metricsCollector else { return }
        collector.recordDisconnect(reason: reason)
        let metrics = collector.finalize()
        metricsCollector = nil

        Task {
            await TelemetryAggregator.shared.record(metrics)
        }
        onSessionMetrics?(metrics)
    }

    private func awaitFinalTranscriptWithForceCheck(timeout: TimeInterval) async -> String {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if forceInjectRequested {
                Self.logger.info("Force inject: using accumulated text")
                return await engine.getTranscription()
            }

            if let final = await engine.getFinalTranscript() {
                return final
            }

            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        return await engine.getTranscription()
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
            metricsCollector?.recordDisconnect(reason: .userInitiated)
            await finishAndInject(reason: .userInitiated)
        case .connecting, .reconnecting:
            await cancelConnecting()
        case .finalizing:
            forceInject()
        case .error:
            setState(.idle)
        }
    }

    private func forceInject() {
        Self.logger.info("Force inject requested")
        forceInjectRequested = true
    }

    private func cancelConnecting() async {
        Self.logger.info("Cancelling connection")
        currentSessionID = nil
        await engine.disconnect()
        stopAudioSendPipeline()
        finalizeMetrics(reason: .cancelled)
        setState(.idle)
    }

    private func startListening() async {
        let sessionID = UUID()
        currentSessionID = sessionID

        let collector = SessionMetricsCollector(sessionID: sessionID)
        metricsCollector = collector

        setState(.connecting)
        droppedBufferCount = 0
        isSpeaking = false
        shouldRetryOnError = true

        do {
            collector.recordConnectionStart()
            try await engine.connect()
            collector.recordConnectionEstablished()

            guard currentSessionID == sessionID else {
                Self.logger.info("Session cancelled before recording started")
                await engine.disconnect()
                finalizeMetrics(reason: .cancelled)
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
                let reason: DisconnectReason
                if case TranscriptionError.connectionTimeout = error {
                    reason = .connectionTimeout
                } else {
                    reason = .fatalError(error.localizedDescription)
                }
                finalizeMetrics(reason: reason)
                setState(.error(error.localizedDescription))
                currentSessionID = nil
            }
        }
    }

    private func handleAudioSamples(_ samples: [Float]) {
        guard case .listening = state, currentSessionID != nil else { return }

        if let continuation = audioBufferContinuation {
            switch continuation.yield(samples) {
            case .enqueued:
                metricsCollector?.recordAudioBufferSent()
            case .dropped:
                metricsCollector?.recordAudioBufferDropped()
                droppedBufferCount += 1
            case .terminated:
                break
            @unknown default:
                break
            }
        } else {
            metricsCollector?.recordAudioBufferDropped()
            droppedBufferCount += 1
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
