import XCTest
@testable import CmdSpeakCore

final class ConfigTests: XCTestCase {
    func testDefaultConfig() {
        let config = Config.default

        XCTAssertEqual(config.model.type, "local")
        XCTAssertEqual(config.model.name, "large-v3-turbo")
        XCTAssertEqual(config.hotkey.trigger, "double-tap-right-cmd")
        XCTAssertEqual(config.hotkey.intervalMs, 300)
        XCTAssertEqual(config.audio.sampleRate, 16000)
        XCTAssertEqual(config.audio.silenceThresholdMs, 500)
        XCTAssertTrue(config.feedback.soundEnabled)
        XCTAssertTrue(config.feedback.menuBarIcon)
    }

    func testModelConfig() {
        let model = ModelConfig(type: "api", name: "gpt-4o-transcribe", provider: "openai")

        XCTAssertEqual(model.type, "api")
        XCTAssertEqual(model.name, "gpt-4o-transcribe")
        XCTAssertEqual(model.provider, "openai")
    }

    func testHotkeyConfigCodable() throws {
        let config = HotkeyConfig(trigger: "double-tap-left-cmd", intervalMs: 200)

        let encoder = JSONEncoder()
        let data = try encoder.encode(config)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(HotkeyConfig.self, from: data)

        XCTAssertEqual(decoded.trigger, "double-tap-left-cmd")
        XCTAssertEqual(decoded.intervalMs, 200)
    }
}
