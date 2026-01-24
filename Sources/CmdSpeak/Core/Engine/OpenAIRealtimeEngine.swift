import Foundation
import os

/// OpenAI Realtime API transcription engine using WebSocket.
/// Uses gpt-4o-transcribe model for real-time speech-to-text.
public actor OpenAIRealtimeEngine: TranscriptionEngine {
    private static let logger = Logger(subsystem: "com.cmdspeak", category: "openai-realtime")

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
    private var onError: (@Sendable (String) -> Void)?
    private var onFinalTranscript: (@Sendable (String) -> Void)?
    private var pingTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?

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

        try await configureSession()
        startReceiving()
        startPingTimer()

        try await waitForSessionReady()

        Self.logger.info("WebSocket connected and session ready")
    }

    private func waitForSessionReady() async throws {
        let deadline = Date().addingTimeInterval(Self.sessionReadyTimeout)

        while !sessionCreated {
            if Date() > deadline {
                disconnect()
                throw TranscriptionError.transcriptionFailed("Session creation timed out")
            }
            try await Task.sleep(nanoseconds: 20_000_000)
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
        urlSession = nil
        sessionCreated = false
    }

    public func setOnDisconnect(_ handler: (@Sendable (Bool) -> Void)?) {
        onDisconnect = handler
    }

    public func setOnError(_ handler: (@Sendable (String) -> Void)?) {
        onError = handler
    }

    public func setOnFinalTranscript(_ handler: (@Sendable (String) -> Void)?) {
        onFinalTranscript = handler
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

        let event: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": base64Audio
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: event)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        try await ws.send(.string(jsonString))
    }

    public func commitAudio() async throws {
        guard let ws = webSocket else {
            throw TranscriptionError.notInitialized
        }

        let event: [String: Any] = [
            "type": "input_audio_buffer.commit"
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: event)
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
        let deadline = Date().addingTimeInterval(timeout)

        while finalTranscript == nil && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        return finalTranscript ?? accumulatedText
    }

    private func configureSession() async throws {
        guard let ws = webSocket else { return }

        var transcriptionConfig: [String: Any] = [
            "model": model,
            "prompt": "Transcribe in any language including mixed language content"
        ]

        if let lang = language {
            transcriptionConfig["language"] = lang
        }

        let sessionConfig: [String: Any] = [
            "type": "transcription_session.update",
            "session": [
                "input_audio_format": "pcm16",
                "input_audio_transcription": transcriptionConfig,
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": 0.5,
                    "prefix_padding_ms": 100,
                    "silence_duration_ms": 300
                ] as [String: Any]
            ] as [String: Any]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: sessionConfig)
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

    private func handleMessage(_ text: String) async {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventType = json["type"] as? String else {
            Self.logger.warning("Received malformed message")
            return
        }

        switch eventType {
        case "transcription_session.created":
            sessionCreated = true
            Self.logger.info("Transcription session created")

        case "transcription_session.updated":
            Self.logger.debug("Transcription session updated")

        case "conversation.item.input_audio_transcription.delta":
            if let delta = json["delta"] as? String {
                accumulatedText += delta
                partialTranscriptionHandler?(delta)
            }

        case "conversation.item.input_audio_transcription.completed":
            if let transcript = json["transcript"] as? String {
                if accumulatedText.isEmpty {
                    accumulatedText = transcript
                }
                finalTranscript = accumulatedText
                let totalChars = accumulatedText.count
                Self.logger.info("Segment completed: \(transcript.count) chars, total: \(totalChars) chars")
                onFinalTranscript?(accumulatedText)
            }

        case "input_audio_buffer.speech_started":
            Self.logger.debug("Speech started")

        case "input_audio_buffer.speech_stopped":
            Self.logger.debug("Speech stopped")

        case "input_audio_buffer.committed":
            Self.logger.debug("Audio committed by server")

        case "error":
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                let code = error["code"] as? String ?? "unknown"
                Self.logger.error("API error [\(code)]: \(message)")
                onError?(message)
            }

        default:
            break
        }
    }

    private func convertToPCM16(samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16Value = Int16(clamped * Float(Int16.max))
            withUnsafeBytes(of: int16Value.littleEndian) { bytes in
                data.append(contentsOf: bytes)
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
