import Foundation
import TOMLKit

/// CmdSpeak configuration.
public struct Config: Codable, Sendable {
    public var model: ModelConfig
    public var hotkey: HotkeyConfig
    public var audio: AudioConfig
    public var feedback: FeedbackConfig

    public init(
        model: ModelConfig = ModelConfig(),
        hotkey: HotkeyConfig = HotkeyConfig(),
        audio: AudioConfig = AudioConfig(),
        feedback: FeedbackConfig = FeedbackConfig()
    ) {
        self.model = model
        self.hotkey = hotkey
        self.audio = audio
        self.feedback = feedback
    }

    public static let `default` = Config()
}

public struct ModelConfig: Codable, Sendable {
    public var type: String
    public var name: String
    public var provider: String?
    public var apiKey: String?

    public init(
        type: String = "local",
        name: String = "openai_whisper-base",
        provider: String? = nil,
        apiKey: String? = nil
    ) {
        self.type = type
        self.name = name
        self.provider = provider
        self.apiKey = apiKey
    }
}

public struct HotkeyConfig: Codable, Sendable {
    public var trigger: String
    public var intervalMs: Int

    public init(trigger: String = "double-tap-right-cmd", intervalMs: Int = 300) {
        self.trigger = trigger
        self.intervalMs = intervalMs
    }

    enum CodingKeys: String, CodingKey {
        case trigger
        case intervalMs = "interval_ms"
    }
}

public struct AudioConfig: Codable, Sendable {
    public var sampleRate: Int
    public var silenceThresholdMs: Int

    public init(sampleRate: Int = 16000, silenceThresholdMs: Int = 500) {
        self.sampleRate = sampleRate
        self.silenceThresholdMs = silenceThresholdMs
    }

    enum CodingKeys: String, CodingKey {
        case sampleRate = "sample_rate"
        case silenceThresholdMs = "silence_threshold_ms"
    }
}

public struct FeedbackConfig: Codable, Sendable {
    public var soundEnabled: Bool
    public var menuBarIcon: Bool

    public init(soundEnabled: Bool = true, menuBarIcon: Bool = true) {
        self.soundEnabled = soundEnabled
        self.menuBarIcon = menuBarIcon
    }

    enum CodingKeys: String, CodingKey {
        case soundEnabled = "sound_enabled"
        case menuBarIcon = "menu_bar_icon"
    }
}

/// Manages loading and saving configuration.
public final class ConfigManager {
    public static let shared = ConfigManager()

    private let configPath: URL

    public init() {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("cmdspeak")
        configPath = configDir.appendingPathComponent("config.toml")
    }

    public func load() throws -> Config {
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            return Config.default
        }

        let content = try String(contentsOf: configPath, encoding: .utf8)
        let table = try TOMLTable(string: content)

        return try parseConfig(from: table)
    }

    public func save(_ config: Config) throws {
        let dir = configPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let toml = generateTOML(from: config)
        try toml.write(to: configPath, atomically: true, encoding: .utf8)
    }

    public func createDefaultIfNeeded() throws {
        guard !FileManager.default.fileExists(atPath: configPath.path) else { return }
        try save(Config.default)
    }

    private func parseConfig(from table: TOMLTable) throws -> Config {
        var config = Config.default

        if let model = table["model"] as? TOMLTable {
            if let type = model["type"] as? String { config.model.type = type }
            if let name = model["name"] as? String { config.model.name = name }
            if let provider = model["provider"] as? String { config.model.provider = provider }
            if let apiKey = model["api_key"] as? String {
                config.model.apiKey = resolveEnvValue(apiKey)
            }
        }

        if let hotkey = table["hotkey"] as? TOMLTable {
            if let trigger = hotkey["trigger"] as? String { config.hotkey.trigger = trigger }
            if let interval = hotkey["interval_ms"] as? Int { config.hotkey.intervalMs = interval }
        }

        if let audio = table["audio"] as? TOMLTable {
            if let rate = audio["sample_rate"] as? Int { config.audio.sampleRate = rate }
            if let silence = audio["silence_threshold_ms"] as? Int {
                config.audio.silenceThresholdMs = silence
            }
        }

        if let feedback = table["feedback"] as? TOMLTable {
            if let sound = feedback["sound_enabled"] as? Bool { config.feedback.soundEnabled = sound }
            if let icon = feedback["menu_bar_icon"] as? Bool { config.feedback.menuBarIcon = icon }
        }

        return config
    }

    private func generateTOML(from config: Config) -> String {
        """
        [model]
        type = "\(config.model.type)"
        name = "\(config.model.name)"

        [hotkey]
        trigger = "\(config.hotkey.trigger)"
        interval_ms = \(config.hotkey.intervalMs)

        [audio]
        sample_rate = \(config.audio.sampleRate)
        silence_threshold_ms = \(config.audio.silenceThresholdMs)

        [feedback]
        sound_enabled = \(config.feedback.soundEnabled)
        menu_bar_icon = \(config.feedback.menuBarIcon)
        """
    }

    private func resolveEnvValue(_ value: String) -> String {
        if value.hasPrefix("env:") {
            let envName = String(value.dropFirst(4))
            return ProcessInfo.processInfo.environment[envName] ?? ""
        }
        return value
    }
}
