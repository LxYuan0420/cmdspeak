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
