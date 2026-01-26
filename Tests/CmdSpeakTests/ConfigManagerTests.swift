import Foundation
import Testing
@testable import CmdSpeakCore

@Suite("ConfigManager Tests")
struct ConfigManagerTests {
    @Test("Environment variable resolution")
    func testEnvVarResolution() {
        let config = ModelConfig(
            type: "api",
            name: "gpt-4o-transcribe",
            provider: "openai",
            apiKey: "env:TEST_API_KEY"
        )

        #expect(config.apiKey == "env:TEST_API_KEY")
    }

    @Test("Default config values are sensible")
    func testDefaultConfigValues() {
        let config = Config.default

        #expect(config.model.type == "local")
        #expect(config.model.name == ModelConfig.defaultLocalModel)
        #expect(config.model.translateToEnglish == false)
        #expect(config.model.language == nil)

        #expect(config.hotkey.trigger == "double-tap-right-option")
        #expect(config.hotkey.intervalMs == 300)

        #expect(config.audio.sampleRate == 16000)
        #expect(config.audio.silenceThresholdMs == 10000)

        #expect(config.feedback.soundEnabled == true)
        #expect(config.feedback.menuBarIcon == true)
    }

    @Test("Audio config Codable roundtrip")
    func testAudioConfigCodable() throws {
        let audio = AudioConfig(sampleRate: 44100, silenceThresholdMs: 1000)

        let encoder = JSONEncoder()
        let data = try encoder.encode(audio)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AudioConfig.self, from: data)

        #expect(decoded.sampleRate == 44100)
        #expect(decoded.silenceThresholdMs == 1000)
    }

    @Test("Feedback config Codable roundtrip")
    func testFeedbackConfigCodable() throws {
        let feedback = FeedbackConfig(soundEnabled: false, menuBarIcon: false)

        let encoder = JSONEncoder()
        let data = try encoder.encode(feedback)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FeedbackConfig.self, from: data)

        #expect(decoded.soundEnabled == false)
        #expect(decoded.menuBarIcon == false)
    }
}
