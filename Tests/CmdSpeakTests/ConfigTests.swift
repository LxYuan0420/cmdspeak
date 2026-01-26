import Foundation
import Testing
@testable import CmdSpeakCore

@Suite("Config Tests")
struct ConfigTests {
    @Test("Default config has expected values")
    func testDefaultConfig() {
        let config = Config.default

        #expect(config.model.type == "local")
        #expect(config.model.name == ModelConfig.defaultLocalModel)
        #expect(config.hotkey.trigger == "double-tap-right-option")
        #expect(config.hotkey.intervalMs == 300)
        #expect(config.audio.sampleRate == 16000)
        #expect(config.audio.silenceThresholdMs == 10000)
        #expect(config.feedback.soundEnabled == true)
        #expect(config.feedback.menuBarIcon == true)
    }

    @Test("Model config stores values correctly")
    func testModelConfig() {
        let model = ModelConfig(type: "api", name: "gpt-4o-transcribe", provider: "openai")

        #expect(model.type == "api")
        #expect(model.name == "gpt-4o-transcribe")
        #expect(model.provider == "openai")
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

    @Test("Translation config is preserved")
    func testTranslationConfig() {
        let model = ModelConfig(
            type: "local",
            name: "whisper-base",
            language: "zh",
            translateToEnglish: true
        )

        #expect(model.language == "zh")
        #expect(model.translateToEnglish == true)
    }
}
