import Foundation
import Testing
@testable import CmdSpeakCore

final class AtomicValue<T: Sendable>: @unchecked Sendable {
    private var _value: T
    private let lock = NSLock()

    init(_ value: T) {
        self._value = value
    }

    var value: T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }
}

@Suite("OpenAI Realtime Engine Tests")
struct OpenAIRealtimeEngineTests {

    // MARK: - Initialization Tests

    @Test("Initialize succeeds with valid API key")
    func testInitializeWithValidKey() async throws {
        let engine = OpenAIRealtimeEngine(apiKey: "test-api-key")
        try await engine.initialize()

        let isReady = await engine.isReady
        #expect(isReady == true)
    }

    @Test("Initialize fails with empty API key")
    func testInitializeWithEmptyKey() async {
        let engine = OpenAIRealtimeEngine(apiKey: "")

        do {
            try await engine.initialize()
            Issue.record("Expected error for empty API key")
        } catch let error as TranscriptionError {
            if case .modelLoadFailed(let message) = error {
                #expect(message.contains("OPENAI_API_KEY"))
            } else {
                Issue.record("Expected modelLoadFailed error")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Initialize fails with empty model name")
    func testInitializeWithEmptyModel() async {
        let engine = OpenAIRealtimeEngine(apiKey: "test-key", model: "")

        do {
            try await engine.initialize()
            Issue.record("Expected error for empty model")
        } catch let error as TranscriptionError {
            if case .modelLoadFailed(let message) = error {
                #expect(message.contains("Model name"))
            } else {
                Issue.record("Expected modelLoadFailed error")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Engine uses default model when not specified")
    func testDefaultModel() async throws {
        let engine = OpenAIRealtimeEngine(apiKey: "test-key")
        try await engine.initialize()

        let isReady = await engine.isReady
        #expect(isReady == true)
    }

    // MARK: - Unload Tests

    @Test("Unload sets isReady to false")
    func testUnloadSetsNotReady() async throws {
        let engine = OpenAIRealtimeEngine(apiKey: "test-key")
        try await engine.initialize()

        var isReady = await engine.isReady
        #expect(isReady == true)

        await engine.unload()

        isReady = await engine.isReady
        #expect(isReady == false)
    }

    // MARK: - Transcription State Tests

    @Test("Initial transcription is empty")
    func testInitialTranscriptionEmpty() async throws {
        let engine = OpenAIRealtimeEngine(apiKey: "test-key")
        try await engine.initialize()

        let text = await engine.getTranscription()
        #expect(text == "")
    }

    @Test("Clear transcription resets accumulated text")
    func testClearTranscription() async throws {
        let engine = OpenAIRealtimeEngine(apiKey: "test-key")
        try await engine.initialize()

        await engine.clearTranscription()

        let text = await engine.getTranscription()
        #expect(text == "")
    }

    // MARK: - Direct transcribe() Tests

    @Test("Direct transcribe throws error")
    func testDirectTranscribeThrows() async throws {
        let engine = OpenAIRealtimeEngine(apiKey: "test-key")
        try await engine.initialize()

        do {
            _ = try await engine.transcribe(audioSamples: [0.1, 0.2, 0.3])
            Issue.record("Expected transcriptionFailed error")
        } catch let error as TranscriptionError {
            if case .transcriptionFailed(let message) = error {
                #expect(message.contains("startStreaming"))
            } else {
                Issue.record("Expected transcriptionFailed error")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - Connect Without Initialize Tests

    @Test("Connect fails when not initialized")
    func testConnectWithoutInitialize() async {
        let engine = OpenAIRealtimeEngine(apiKey: "test-key")

        do {
            try await engine.connect()
            Issue.record("Expected notInitialized error")
        } catch let error as TranscriptionError {
            if case .notInitialized = error {
                #expect(true)
            } else {
                Issue.record("Expected notInitialized error, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - sendAudio Without Connection Tests

    @Test("sendAudio fails when not connected")
    func testSendAudioWithoutConnection() async throws {
        let engine = OpenAIRealtimeEngine(apiKey: "test-key")
        try await engine.initialize()

        do {
            try await engine.sendAudio(samples: [0.5, -0.5])
            Issue.record("Expected notInitialized error")
        } catch let error as TranscriptionError {
            if case .notInitialized = error {
                #expect(true)
            } else {
                Issue.record("Expected notInitialized error, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - commitAudio Without Connection Tests

    @Test("commitAudio fails when not connected")
    func testCommitAudioWithoutConnection() async throws {
        let engine = OpenAIRealtimeEngine(apiKey: "test-key")
        try await engine.initialize()

        do {
            try await engine.commitAudio()
            Issue.record("Expected notInitialized error")
        } catch let error as TranscriptionError {
            if case .notInitialized = error {
                #expect(true)
            } else {
                Issue.record("Expected notInitialized error, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - Language Configuration Tests

    @Test("Engine accepts language parameter")
    func testLanguageParameter() async throws {
        let engine = OpenAIRealtimeEngine(apiKey: "test-key", language: "zh")
        try await engine.initialize()

        let isReady = await engine.isReady
        #expect(isReady == true)
    }

    @Test("Engine works without language parameter")
    func testNoLanguageParameter() async throws {
        let engine = OpenAIRealtimeEngine(apiKey: "test-key", language: nil)
        try await engine.initialize()

        let isReady = await engine.isReady
        #expect(isReady == true)
    }
}

// MARK: - PCM16 Conversion Tests

@Suite("PCM16 Conversion Tests")
struct PCM16ConversionTests {

    @Test("PCM16 conversion produces correct byte count")
    func testPCM16ByteCount() {
        let samples: [Float] = [0.0, 0.5, -0.5, 1.0, -1.0]
        let data = convertToPCM16TestHelper(samples: samples)

        #expect(data.count == samples.count * 2)
    }

    @Test("PCM16 conversion clamps values above 1.0")
    func testPCM16ClampsHigh() {
        let samples: [Float] = [1.5, 2.0, 10.0]
        let data = convertToPCM16TestHelper(samples: samples)

        let values = extractInt16Values(from: data)
        for value in values {
            #expect(value == Int16.max)
        }
    }

    @Test("PCM16 conversion clamps values below -1.0")
    func testPCM16ClampsLow() {
        let samples: [Float] = [-1.5, -2.0, -10.0]
        let data = convertToPCM16TestHelper(samples: samples)

        let values = extractInt16Values(from: data)
        for value in values {
            #expect(value == Int16.min + 1)
        }
    }

    @Test("PCM16 conversion zero produces zero")
    func testPCM16Zero() {
        let samples: [Float] = [0.0]
        let data = convertToPCM16TestHelper(samples: samples)

        let values = extractInt16Values(from: data)
        #expect(values[0] == 0)
    }

    @Test("PCM16 conversion positive produces positive")
    func testPCM16Positive() {
        let samples: [Float] = [0.5]
        let data = convertToPCM16TestHelper(samples: samples)

        let values = extractInt16Values(from: data)
        #expect(values[0] > 0)
        #expect(values[0] == Int16(0.5 * Float(Int16.max)))
    }

    @Test("PCM16 conversion negative produces negative")
    func testPCM16Negative() {
        let samples: [Float] = [-0.5]
        let data = convertToPCM16TestHelper(samples: samples)

        let values = extractInt16Values(from: data)
        #expect(values[0] < 0)
    }

    @Test("PCM16 conversion max value")
    func testPCM16MaxValue() {
        let samples: [Float] = [1.0]
        let data = convertToPCM16TestHelper(samples: samples)

        let values = extractInt16Values(from: data)
        #expect(values[0] == Int16.max)
    }

    @Test("PCM16 conversion min value")
    func testPCM16MinValue() {
        let samples: [Float] = [-1.0]
        let data = convertToPCM16TestHelper(samples: samples)

        let values = extractInt16Values(from: data)
        #expect(values[0] == Int16.min + 1)
    }

    @Test("PCM16 uses little endian format")
    func testPCM16LittleEndian() {
        let samples: [Float] = [0.5]
        let data = convertToPCM16TestHelper(samples: samples)

        let expectedValue = Int16(0.5 * Float(Int16.max))
        let lowByte = UInt8(expectedValue.littleEndian & 0xFF)
        let highByte = UInt8((expectedValue.littleEndian >> 8) & 0xFF)

        #expect(data[0] == lowByte)
        #expect(data[1] == highByte)
    }

    private func convertToPCM16TestHelper(samples: [Float]) -> Data {
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

    private func extractInt16Values(from data: Data) -> [Int16] {
        var values: [Int16] = []
        for i in stride(from: 0, to: data.count, by: 2) {
            let value = data.withUnsafeBytes { ptr in
                ptr.load(fromByteOffset: i, as: Int16.self)
            }
            values.append(Int16(littleEndian: value))
        }
        return values
    }
}

// MARK: - Message Handling Tests

@Suite("Message Handling Tests")
struct MessageHandlingTests {

    @Test("Partial transcription handler is called on delta")
    func testPartialTranscriptionHandler() async throws {
        let engine = OpenAIRealtimeEngine(apiKey: "test-key")
        try await engine.initialize()

        let receivedDelta = AtomicValue<String?>(nil)
        await engine.setPartialTranscriptionHandler { delta in
            receivedDelta.value = delta
        }

        let deltaMessage = """
        {"type": "conversation.item.input_audio_transcription.delta", "delta": "Hello"}
        """
        await engine.testHandleMessage(deltaMessage)

        #expect(receivedDelta.value == "Hello")

        let text = await engine.getTranscription()
        #expect(text == "Hello")
    }

    @Test("Multiple deltas accumulate")
    func testMultipleDeltasAccumulate() async throws {
        let engine = OpenAIRealtimeEngine(apiKey: "test-key")
        try await engine.initialize()

        await engine.testHandleMessage("""
        {"type": "conversation.item.input_audio_transcription.delta", "delta": "Hello"}
        """)
        await engine.testHandleMessage("""
        {"type": "conversation.item.input_audio_transcription.delta", "delta": " world"}
        """)

        let text = await engine.getTranscription()
        #expect(text == "Hello world")
    }

    @Test("Completed event with empty accumulator uses transcript")
    func testCompletedWithEmptyAccumulator() async throws {
        let engine = OpenAIRealtimeEngine(apiKey: "test-key")
        try await engine.initialize()

        await engine.testHandleMessage("""
        {"type": "conversation.item.input_audio_transcription.completed", "transcript": "Final text"}
        """)

        let text = await engine.getTranscription()
        #expect(text == "Final text")
    }

    @Test("Completed event preserves accumulated text")
    func testCompletedPreservesAccumulatedText() async throws {
        let engine = OpenAIRealtimeEngine(apiKey: "test-key")
        try await engine.initialize()

        await engine.testHandleMessage("""
        {"type": "conversation.item.input_audio_transcription.delta", "delta": "Hello world"}
        """)
        await engine.testHandleMessage("""
        {"type": "conversation.item.input_audio_transcription.completed", "transcript": "Hello world"}
        """)

        let text = await engine.getTranscription()
        #expect(text == "Hello world")

        let finalText = await engine.getFinalTranscript()
        #expect(finalText == "Hello world")
    }

    @Test("Multiple speech segments preserve all accumulated text - regression test")
    func testMultipleSegmentsPreserveAllText() async throws {
        let engine = OpenAIRealtimeEngine(apiKey: "test-key")
        try await engine.initialize()

        await engine.testHandleMessage("""
        {"type": "conversation.item.input_audio_transcription.delta", "delta": "First sentence. "}
        """)
        await engine.testHandleMessage("""
        {"type": "conversation.item.input_audio_transcription.completed", "transcript": "First sentence. "}
        """)

        await engine.testHandleMessage("""
        {"type": "conversation.item.input_audio_transcription.delta", "delta": "Second sentence. "}
        """)
        await engine.testHandleMessage("""
        {"type": "conversation.item.input_audio_transcription.completed", "transcript": "Second sentence. "}
        """)

        await engine.testHandleMessage("""
        {"type": "conversation.item.input_audio_transcription.delta", "delta": "Third sentence."}
        """)
        await engine.testHandleMessage("""
        {"type": "conversation.item.input_audio_transcription.completed", "transcript": "Third sentence."}
        """)

        let text = await engine.getTranscription()
        #expect(text == "First sentence. Second sentence. Third sentence.")

        let finalText = await engine.getFinalTranscript()
        #expect(finalText == "First sentence. Second sentence. Third sentence.")
    }

    @Test("Completed event does not overwrite accumulated text with segment-only text")
    func testCompletedDoesNotOverwrite() async throws {
        let engine = OpenAIRealtimeEngine(apiKey: "test-key")
        try await engine.initialize()

        await engine.testHandleMessage("""
        {"type": "conversation.item.input_audio_transcription.delta", "delta": "I can double tap. "}
        """)
        await engine.testHandleMessage("""
        {"type": "conversation.item.input_audio_transcription.completed", "transcript": "I can double tap. "}
        """)

        await engine.testHandleMessage("""
        {"type": "conversation.item.input_audio_transcription.delta", "delta": "But only last words appear."}
        """)
        await engine.testHandleMessage("""
        {"type": "conversation.item.input_audio_transcription.completed", "transcript": "But only last words appear."}
        """)

        let text = await engine.getTranscription()
        #expect(text.contains("I can double tap"))
        #expect(text.contains("But only last words appear"))
        #expect(text == "I can double tap. But only last words appear.")
    }

    @Test("Error event calls error handler")
    func testErrorEventCallsHandler() async throws {
        let engine = OpenAIRealtimeEngine(apiKey: "test-key")
        try await engine.initialize()

        let receivedError = AtomicValue<RealtimeAPIError?>(nil)
        await engine.setOnError { error in
            receivedError.value = error
        }

        await engine.testHandleMessage("""
        {"type": "error", "error": {"message": "Rate limit exceeded"}}
        """)

        #expect(receivedError.value?.message == "Rate limit exceeded")
    }

    @Test("Invalid JSON is ignored")
    func testInvalidJSONIgnored() async throws {
        let engine = OpenAIRealtimeEngine(apiKey: "test-key")
        try await engine.initialize()

        await engine.testHandleMessage("not valid json")

        let text = await engine.getTranscription()
        #expect(text == "")
    }

    @Test("Missing type field is ignored")
    func testMissingTypeIgnored() async throws {
        let engine = OpenAIRealtimeEngine(apiKey: "test-key")
        try await engine.initialize()

        await engine.testHandleMessage("""
        {"delta": "Hello"}
        """)

        let text = await engine.getTranscription()
        #expect(text == "")
    }

    @Test("Unknown event types are handled gracefully")
    func testUnknownEventTypes() async throws {
        let engine = OpenAIRealtimeEngine(apiKey: "test-key")
        try await engine.initialize()

        await engine.testHandleMessage("""
        {"type": "unknown.event.type"}
        """)

        let text = await engine.getTranscription()
        #expect(text == "")
    }

    @Test("Session created event is handled")
    func testSessionCreatedEvent() async throws {
        let engine = OpenAIRealtimeEngine(apiKey: "test-key")
        try await engine.initialize()

        await engine.testHandleMessage("""
        {"type": "transcription_session.created"}
        """)

        let text = await engine.getTranscription()
        #expect(text == "")
    }

    @Test("Speech started event is handled")
    func testSpeechStartedEvent() async throws {
        let engine = OpenAIRealtimeEngine(apiKey: "test-key")
        try await engine.initialize()

        await engine.testHandleMessage("""
        {"type": "input_audio_buffer.speech_started"}
        """)

        let text = await engine.getTranscription()
        #expect(text == "")
    }

    @Test("Speech stopped event is handled")
    func testSpeechStoppedEvent() async throws {
        let engine = OpenAIRealtimeEngine(apiKey: "test-key")
        try await engine.initialize()

        await engine.testHandleMessage("""
        {"type": "input_audio_buffer.speech_stopped"}
        """)

        let text = await engine.getTranscription()
        #expect(text == "")
    }

    @Test("Speech started callback is invoked")
    func testSpeechStartedCallback() async throws {
        let engine = OpenAIRealtimeEngine(apiKey: "test-key")
        try await engine.initialize()

        let callbackInvoked = AtomicValue(false)
        await engine.setOnSpeechStarted {
            callbackInvoked.value = true
        }

        await engine.testHandleMessage("""
        {"type": "input_audio_buffer.speech_started"}
        """)

        #expect(callbackInvoked.value == true)
    }

    @Test("Speech stopped callback is invoked")
    func testSpeechStoppedCallback() async throws {
        let engine = OpenAIRealtimeEngine(apiKey: "test-key")
        try await engine.initialize()

        let callbackInvoked = AtomicValue(false)
        await engine.setOnSpeechStopped {
            callbackInvoked.value = true
        }

        await engine.testHandleMessage("""
        {"type": "input_audio_buffer.speech_stopped"}
        """)

        #expect(callbackInvoked.value == true)
    }
}

// MARK: - Handler Configuration Tests

// MARK: - Connection Timeout Tests

@Suite("Connection Timeout Tests")
struct ConnectionTimeoutTests {

    @Test("ConnectionTimeout error has correct description")
    func testConnectionTimeoutErrorDescription() {
        let error = TranscriptionError.connectionTimeout
        #expect(error.errorDescription == "Connection timed out")
    }

    @Test("ConnectionTimeout is distinct from other errors")
    func testConnectionTimeoutDistinct() {
        let timeoutError = TranscriptionError.connectionTimeout
        let notInitError = TranscriptionError.notInitialized

        if case .connectionTimeout = timeoutError {
            #expect(true)
        } else {
            Issue.record("Expected connectionTimeout case")
        }

        if case .connectionTimeout = notInitError {
            Issue.record("notInitialized should not match connectionTimeout")
        } else {
            #expect(true)
        }
    }

    @Test("ConnectionTimeout can be caught and handled")
    func testConnectionTimeoutCatching() async {
        func simulateTimeout() throws {
            throw TranscriptionError.connectionTimeout
        }

        do {
            try simulateTimeout()
            Issue.record("Expected connectionTimeout error")
        } catch let error as TranscriptionError {
            if case .connectionTimeout = error {
                #expect(true)
            } else {
                Issue.record("Expected connectionTimeout, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

@Suite("Handler Configuration Tests")
struct HandlerConfigurationTests {

    @Test("Set and clear partial transcription handler")
    func testSetClearPartialHandler() async throws {
        let engine = OpenAIRealtimeEngine(apiKey: "test-key")
        try await engine.initialize()

        let callCount = AtomicValue(0)
        await engine.setPartialTranscriptionHandler { _ in
            callCount.value += 1
        }

        await engine.testHandleMessage("""
        {"type": "conversation.item.input_audio_transcription.delta", "delta": "test"}
        """)
        #expect(callCount.value == 1)

        await engine.setPartialTranscriptionHandler(nil)

        await engine.testHandleMessage("""
        {"type": "conversation.item.input_audio_transcription.delta", "delta": "test2"}
        """)
        #expect(callCount.value == 1)
    }

    @Test("Set and clear error handler")
    func testSetClearErrorHandler() async throws {
        let engine = OpenAIRealtimeEngine(apiKey: "test-key")
        try await engine.initialize()

        let callCount = AtomicValue(0)
        await engine.setOnError { _ in
            callCount.value += 1
        }

        await engine.testHandleMessage("""
        {"type": "error", "error": {"message": "test error"}}
        """)
        #expect(callCount.value == 1)

        await engine.setOnError(nil)

        await engine.testHandleMessage("""
        {"type": "error", "error": {"message": "test error 2"}}
        """)
        #expect(callCount.value == 1)
    }
}
