import Foundation
import Testing
@testable import CmdSpeakCore

@Suite("Config Tests")
struct ConfigTests {
    @Test("Default config has expected values")
    func testDefaultConfig() {
        let config = Config.default

        #expect(config.model.name == "gpt-4o-transcribe")
        #expect(config.hotkey.trigger == "double-tap-right-option")
        #expect(config.hotkey.intervalMs == 300)
        #expect(config.audio.sampleRate == 24000)
        #expect(config.audio.silenceThresholdMs == 10000)
        #expect(config.feedback.soundEnabled == true)
        #expect(config.feedback.menuBarIcon == true)
    }

    @Test("Model config stores values correctly")
    func testModelConfig() {
        let model = ModelConfig(name: "gpt-4o-transcribe", apiKey: "test-key")

        #expect(model.name == "gpt-4o-transcribe")
        #expect(model.apiKey == "test-key")
    }

    @Test("Hotkey config is Codable")
    func testHotkeyConfigCodable() throws {
        let config = HotkeyConfig(trigger: "double-tap-left-cmd", intervalMs: 200)

        let encoder = JSONEncoder()
        let data = try encoder.encode(config)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(HotkeyConfig.self, from: data)

        #expect(decoded.trigger == "double-tap-left-cmd")
        #expect(decoded.intervalMs == 200)
    }

    @Test("Language config is preserved")
    func testLanguageConfig() {
        let model = ModelConfig(
            name: "gpt-4o-transcribe",
            language: "zh"
        )

        #expect(model.language == "zh")
    }
}
