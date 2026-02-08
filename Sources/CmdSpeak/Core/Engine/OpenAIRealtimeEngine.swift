import Foundation
import os

/// OpenAI Realtime API transcription engine using WebSocket.
/// Uses gpt-4o-transcribe model for real-time speech-to-text.
public actor OpenAIRealtimeEngine: TranscriptionEngine {
    private static let logger = Logger(subsystem: "com.cmdspeak", category: "openai-realtime")

    private static let hallucinationPatterns: [String] = [
        "transcribe in any language",
        "including mixed language content"
    ]

    public private(set) var isReady: Bool = false

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let apiKey: String
    private let model: String
    private let language: String?

    private var accumulatedText: String = ""
    private var finalTranscript: String?

    private let inputSampleRate: Double = 24000
    private var sessionCreated: Bool = false
    private var isClosingIntentionally: Bool = false

    private var partialTranscriptionHandler: (@Sendable (String) -> Void)?
    private var onDisconnect: (@Sendable (Bool) -> Void)?
    private var onError: (@Sendable (RealtimeAPIError) -> Void)?
    private var onFinalTranscript: (@Sendable (String) -> Void)?
    private var onSpeechStarted: (@Sendable () -> Void)?
    private var onSpeechStopped: (@Sendable () -> Void)?
    private var pingTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?

    private var sessionReadyContinuation: CheckedContinuation<Void, Error>?
    private var finalTranscriptContinuation: CheckedContinuation<String, Never>?

    private static let connectionTimeout: TimeInterval = 10.0
    private static let sessionReadyTimeout: TimeInterval = 5.0

    public init(apiKey: String, model: String = "gpt-4o-transcribe", language: String? = nil) {
        self.apiKey = apiKey
        self.model = model
        self.language = language
    }

    public func initialize() async throws {
        guard !apiKey.isEmpty else {
            throw TranscriptionError.modelLoadFailed("OPENAI_API_KEY not set")
        }
        guard !model.isEmpty else {
            throw TranscriptionError.modelLoadFailed("Model name cannot be empty")
        }
        Self.logger.info("OpenAI Realtime Engine initialized (API mode)")
        isReady = true
    }

    public func transcribe(audioSamples: [Float]) async throws -> TranscriptionResult {
        throw TranscriptionError.transcriptionFailed("Use startStreaming/sendAudio/stopStreaming for realtime transcription")
    }

    public func unload() async {
        disconnect()
        isReady = false
    }

    public func connect() async throws {
        guard isReady else {
            throw TranscriptionError.notInitialized
        }

        isClosingIntentionally = false
        finalTranscript = nil

        let url = URL(string: "wss://api.openai.com/v1/realtime?intent=transcription")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let session = URLSession(configuration: .default)
        let ws = session.webSocketTask(with: request)

        self.urlSession = session
        self.webSocket = ws
        self.accumulatedText = ""
        self.sessionCreated = false

        ws.resume()

        try await withConnectionTimeout {
            try await self.configureSession()
            self.startReceiving()
            self.startPingTimer()
            try await self.waitForSessionReady()
        }

        Self.logger.info("WebSocket connected and session ready")
    }

    private func withConnectionTimeout<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(Self.connectionTimeout * 1_000_000_000))
                throw TranscriptionError.connectionTimeout
            }

            guard let result = try await group.next() else {
                throw TranscriptionError.connectionTimeout
            }
            group.cancelAll()
            return result
        }
    }

    private func waitForSessionReady() async throws {
        if sessionCreated { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.sessionReadyContinuation = continuation

            if self.sessionCreated {
                self.sessionReadyContinuation = nil
                continuation.resume()
                return
            }

            Task {
                try? await Task.sleep(nanoseconds: UInt64(Self.sessionReadyTimeout * 1_000_000_000))
                if let cont = self.sessionReadyContinuation {
                    self.sessionReadyContinuation = nil
                    self.disconnect()
                    cont.resume(throwing: TranscriptionError.transcriptionFailed("Session creation timed out"))
                }
            }
        }
    }

    private func signalSessionReady() {
        if let continuation = sessionReadyContinuation {
            sessionReadyContinuation = nil
            continuation.resume()
        }
    }

    public func disconnect() {
        isClosingIntentionally = true
        receiveTask?.cancel()
        receiveTask = nil
        pingTask?.cancel()
        pingTask = nil
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        sessionCreated = false

        if let cont = sessionReadyContinuation {
            sessionReadyContinuation = nil
            cont.resume(throwing: CancellationError())
        }
        if let cont = finalTranscriptContinuation {
            finalTranscriptContinuation = nil
            cont.resume(returning: accumulatedText)
        }
    }

    public func setOnDisconnect(_ handler: (@Sendable (Bool) -> Void)?) {
        onDisconnect = handler
    }

    public func setOnError(_ handler: (@Sendable (RealtimeAPIError) -> Void)?) {
        onError = handler
    }

    public func setOnFinalTranscript(_ handler: (@Sendable (String) -> Void)?) {
        onFinalTranscript = handler
    }

    public func setOnSpeechStarted(_ handler: (@Sendable () -> Void)?) {
        onSpeechStarted = handler
    }

    public func setOnSpeechStopped(_ handler: (@Sendable () -> Void)?) {
        onSpeechStopped = handler
    }

    public var isSessionReady: Bool {
        sessionCreated
    }

    private func startPingTimer() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { break }
                await self?.sendPing()
            }
        }
    }

    private func sendPing() async {
        guard let ws = webSocket else { return }
        ws.sendPing { error in
            if let error = error {
                Self.logger.warning("Ping failed: \(error.localizedDescription)")
            }
        }
    }

    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        return encoder
    }()

    public func sendAudio(samples: [Float]) async throws {
        guard let ws = webSocket else {
            throw TranscriptionError.notInitialized
        }

        guard sessionCreated else {
            Self.logger.debug("Dropping audio: session not ready")
            return
        }

        let pcmData = convertToPCM16(samples: samples)
        let base64Audio = pcmData.base64EncodedString()

        let message = InputAudioBufferAppend(audio: base64Audio)
        let jsonData = try Self.jsonEncoder.encode(message)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        try await ws.send(.string(jsonString))
    }

    public func commitAudio() async throws {
        guard let ws = webSocket else {
            throw TranscriptionError.notInitialized
        }

        let message = InputAudioBufferCommit()
        let jsonData = try Self.jsonEncoder.encode(message)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        try await ws.send(.string(jsonString))
        Self.logger.debug("Audio buffer committed")
    }

    public func getTranscription() -> String {
        return finalTranscript ?? accumulatedText
    }

    public func getFinalTranscript() -> String? {
        return finalTranscript
    }

    public func clearTranscription() {
        accumulatedText = ""
        finalTranscript = nil
    }

    public func setPartialTranscriptionHandler(_ handler: (@Sendable (String) -> Void)?) {
        partialTranscriptionHandler = handler
    }

    public func awaitFinalTranscript(timeout: TimeInterval = 3.0) async -> String {
        if let transcript = finalTranscript {
            return transcript
        }

        if finalTranscriptContinuation != nil {
            return finalTranscript ?? accumulatedText
        }

        return await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            self.finalTranscriptContinuation = continuation

            if let transcript = self.finalTranscript {
                self.finalTranscriptContinuation = nil
                continuation.resume(returning: transcript)
                return
            }

            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if let cont = self.finalTranscriptContinuation {
                    self.finalTranscriptContinuation = nil
                    cont.resume(returning: self.finalTranscript ?? self.accumulatedText)
                }
            }
        }
    }

    private func signalFinalTranscript(_ text: String) {
        if let continuation = finalTranscriptContinuation {
            finalTranscriptContinuation = nil
            continuation.resume(returning: text)
        }
    }

    private func configureSession() async throws {
        guard let ws = webSocket else { return }

        let message = TranscriptionSessionUpdate(model: model, language: language)
        let jsonData = try Self.jsonEncoder.encode(message)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        try await ws.send(.string(jsonString))
        Self.logger.debug("Session configuration sent")
    }

    private func startReceiving() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    private func receiveLoop() async {
        guard let ws = webSocket else { return }

        do {
            while !Task.isCancelled {
                let message = try await ws.receive()

                switch message {
                case .string(let text):
                    await handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await handleMessage(text)
                    }
                @unknown default:
                    break
                }
            }
        } catch {
            let nsError = error as NSError
            let isSocketClosed = nsError.code == 57 || nsError.code == 54
            let wasIntentional = isClosingIntentionally

            if !isSocketClosed && !wasIntentional {
                Self.logger.error("WebSocket error: \(error.localizedDescription) (code: \(nsError.code))")
            }

            if !wasIntentional {
                onDisconnect?(false)
            }
        }
    }

    private static let jsonDecoder = JSONDecoder()

    private func handleMessage(_ text: String) async {
        guard let data = text.data(using: .utf8) else {
            Self.logger.warning("Received non-UTF8 message")
            return
        }

        guard let baseMessage = try? Self.jsonDecoder.decode(OpenAIIncomingMessage.self, from: data) else {
            Self.logger.warning("Received malformed message")
            return
        }

        guard let eventType = OpenAIEventType(rawValue: baseMessage.type) else {
            return
        }

        switch eventType {
        case .sessionCreated:
            sessionCreated = true
            signalSessionReady()
            Self.logger.info("Transcription session created")

        case .sessionUpdated:
            Self.logger.debug("Transcription session updated")

        case .transcriptionDelta:
            if let deltaMessage = try? Self.jsonDecoder.decode(TranscriptionDelta.self, from: data) {
                let delta = deltaMessage.delta
                let lowerDelta = delta.lowercased()
                let isHallucination = Self.hallucinationPatterns.contains { lowerDelta.contains($0) }
                if !isHallucination {
                    accumulatedText += delta
                    partialTranscriptionHandler?(delta)
                } else {
                    Self.logger.debug("Filtered hallucinated text: \(delta)")
                }
            }

        case .transcriptionCompleted:
            if let completedMessage = try? Self.jsonDecoder.decode(TranscriptionCompleted.self, from: data) {
                if accumulatedText.isEmpty {
                    accumulatedText = completedMessage.transcript
                }
                finalTranscript = accumulatedText
                let totalChars = accumulatedText.count
                Self.logger.info("Segment completed: \(completedMessage.transcript.count) chars, total: \(totalChars) chars")
                signalFinalTranscript(accumulatedText)
                onFinalTranscript?(accumulatedText)
            }

        case .speechStarted:
            Self.logger.debug("Speech started")
            onSpeechStarted?()

        case .speechStopped:
            Self.logger.debug("Speech stopped")
            onSpeechStopped?()

        case .audioCommitted:
            Self.logger.debug("Audio committed by server")

        case .error:
            if let errorMessage = try? Self.jsonDecoder.decode(OpenAIError.self, from: data) {
                let code = errorMessage.error.code
                let apiError = RealtimeAPIError(code: code, message: errorMessage.error.message)
                Self.logger.error("API error [\(code ?? "unknown")]: \(errorMessage.error.message)")
                onError?(apiError)
            }
        }
    }

    private func convertToPCM16(samples: [Float]) -> Data {
        var data = Data(count: samples.count * MemoryLayout<Int16>.size)
        data.withUnsafeMutableBytes { raw in
            let out = raw.bindMemory(to: Int16.self)
            for i in samples.indices {
                let clamped = max(-1.0, min(1.0, samples[i]))
                out[i] = Int16(clamped * Float(Int16.max)).littleEndian
            }
        }
        return data
    }

    #if DEBUG
    public func testHandleMessage(_ text: String) async {
        await handleMessage(text)
    }
    #endif
}
