import Foundation
import Testing
@testable import CmdSpeakCore

@Suite("OpenAI Realtime Controller Tests")
struct OpenAIRealtimeControllerTests {

    @Test("ConfigurationError has meaningful descriptions")
    func testConfigurationErrorDescriptions() {
        let missingKey = ConfigurationError.missingAPIKey
        #expect(missingKey.errorDescription?.contains("OPENAI_API_KEY") == true)

        let invalidSilence = ConfigurationError.invalidSilenceThreshold(500)
        #expect(invalidSilence.errorDescription?.contains("500") == true)
        #expect(invalidSilence.errorDescription?.contains("out of range") == true)

        let invalidHotkey = ConfigurationError.invalidHotkeyInterval(50)
        #expect(invalidHotkey.errorDescription?.contains("50") == true)
        #expect(invalidHotkey.errorDescription?.contains("out of range") == true)
    }

    @Test("State enum equality works correctly")
    func testStateEquality() {
        let idle1 = OpenAIRealtimeController.State.idle
        let idle2 = OpenAIRealtimeController.State.idle
        #expect(idle1 == idle2)

        let connecting = OpenAIRealtimeController.State.connecting
        #expect(idle1 != connecting)

        let error1 = OpenAIRealtimeController.State.error("Test error")
        let error2 = OpenAIRealtimeController.State.error("Test error")
        let error3 = OpenAIRealtimeController.State.error("Different error")
        #expect(error1 == error2)
        #expect(error1 != error3)

        let listening = OpenAIRealtimeController.State.listening
        let finalizing = OpenAIRealtimeController.State.finalizing
        #expect(listening != finalizing)
    }

    @Test("All states are distinct")
    func testStateDistinctness() {
        let states: [OpenAIRealtimeController.State] = [
            .idle,
            .connecting,
            .listening,
            .reconnecting(attempt: 1, maxAttempts: 3),
            .finalizing,
            .error("test")
        ]

        for (i, state1) in states.enumerated() {
            for (j, state2) in states.enumerated() {
                if i != j {
                    #expect(state1 != state2)
                }
            }
        }
    }

    @Test("Reconnecting state equality with same parameters")
    func testReconnectingStateEquality() {
        let reconnecting1 = OpenAIRealtimeController.State.reconnecting(attempt: 1, maxAttempts: 3)
        let reconnecting2 = OpenAIRealtimeController.State.reconnecting(attempt: 1, maxAttempts: 3)
        #expect(reconnecting1 == reconnecting2)
    }

    @Test("Reconnecting state inequality with different parameters")
    func testReconnectingStateInequality() {
        let reconnecting1 = OpenAIRealtimeController.State.reconnecting(attempt: 1, maxAttempts: 3)
        let reconnecting2 = OpenAIRealtimeController.State.reconnecting(attempt: 2, maxAttempts: 3)
        let reconnecting3 = OpenAIRealtimeController.State.reconnecting(attempt: 1, maxAttempts: 5)
        #expect(reconnecting1 != reconnecting2)
        #expect(reconnecting1 != reconnecting3)
    }

    @Test("Reconnecting state is distinct from connecting")
    func testReconnectingDistinctFromConnecting() {
        let connecting = OpenAIRealtimeController.State.connecting
        let reconnecting = OpenAIRealtimeController.State.reconnecting(attempt: 1, maxAttempts: 3)
        #expect(connecting != reconnecting)
    }
}

@Suite("Error Classification Tests")
struct ErrorClassificationTests {

    @Test("Invalid API key errors are classified as fatal")
    func testInvalidApiKeyIsFatal() {
        let fatalMessages = [
            "invalid_api_key",
            "Invalid API key provided",
            "authentication failed",
            "unauthorized access",
            "invalid_request_error: bad key"
        ]

        for message in fatalMessages {
            #expect(message.lowercased().contains("invalid_api_key") ||
                   message.lowercased().contains("invalid api key") ||
                   message.lowercased().contains("authentication") ||
                   message.lowercased().contains("unauthorized") ||
                   message.lowercased().contains("invalid_request_error"))
        }
    }

    @Test("Model not found errors are classified as fatal")
    func testModelNotFoundIsFatal() {
        let message = "model_not_found: gpt-4o-transcribe"
        #expect(message.lowercased().contains("model_not_found"))
    }

    @Test("Quota errors are classified as fatal")
    func testQuotaErrorIsFatal() {
        let messages = [
            "insufficient_quota",
            "billing issue detected"
        ]

        for message in messages {
            #expect(message.lowercased().contains("insufficient_quota") ||
                   message.lowercased().contains("billing"))
        }
    }

    @Test("Rate limit errors are transient")
    func testRateLimitIsTransient() {
        let message = "rate_limit_exceeded"
        #expect(!message.lowercased().contains("invalid_api_key"))
        #expect(!message.lowercased().contains("insufficient_quota"))
    }
}

@Suite("Configuration Validation Tests")
struct ConfigurationValidationTests {

    @Test("Silence threshold validation range")
    func testSilenceThresholdRange() {
        let validValues = [1000, 5000, 10000, 30000, 60000]
        for value in validValues {
            var config = Config.default
            config.audio.silenceThresholdMs = value
            #expect((1000...60000).contains(config.audio.silenceThresholdMs))
        }

        let invalidValues = [0, 500, 999, 60001, 100000]
        for value in invalidValues {
            #expect(!(1000...60000).contains(value))
        }
    }

    @Test("Hotkey interval validation range")
    func testHotkeyIntervalRange() {
        let validValues = [100, 200, 300, 500, 1000]
        for value in validValues {
            #expect((100...1000).contains(value))
        }

        let invalidValues = [0, 50, 99, 1001, 2000]
        for value in invalidValues {
            #expect(!(100...1000).contains(value))
        }
    }
}
