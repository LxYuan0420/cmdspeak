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
    public var name: String
    public var apiKey: String?
    public var language: String?

    public init(
        name: String = "gpt-4o-transcribe",
        apiKey: String? = nil,
        language: String? = nil
    ) {
        self.name = name
        self.apiKey = apiKey
        self.language = language
    }

    enum CodingKeys: String, CodingKey {
        case name
        case apiKey = "api_key"
        case language
    }
}

public struct HotkeyConfig: Codable, Sendable {
    public var trigger: String
    public var intervalMs: Int

    public init(trigger: String = "double-tap-right-option", intervalMs: Int = 300) {
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

    public init(sampleRate: Int = 24000, silenceThresholdMs: Int = 10000) {
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

        let decoder = TOMLDecoder()
        do {
            return try decoder.decode(Config.self, from: content)
        } catch {
            let table = try TOMLTable(string: content)
            return try parseConfig(from: table)
        }
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

        if let modelValue = table["model"], let model = modelValue.table {
            if let name = model["name"]?.string { config.model.name = name }
            if let apiKey = model["api_key"]?.string {
                config.model.apiKey = resolveEnvValue(apiKey)
            }
            if let language = model["language"]?.string { config.model.language = language }
        }

        if let hotkeyValue = table["hotkey"], let hotkey = hotkeyValue.table {
            if let trigger = hotkey["trigger"]?.string { config.hotkey.trigger = trigger }
            if let interval = hotkey["interval_ms"]?.int { config.hotkey.intervalMs = Int(interval) }
        }

        if let audioValue = table["audio"], let audio = audioValue.table {
            if let rate = audio["sample_rate"]?.int { config.audio.sampleRate = Int(rate) }
            if let silence = audio["silence_threshold_ms"]?.int {
                config.audio.silenceThresholdMs = Int(silence)
            }
        }

        if let feedbackValue = table["feedback"], let feedback = feedbackValue.table {
            if let sound = feedback["sound_enabled"]?.bool { config.feedback.soundEnabled = sound }
            if let icon = feedback["menu_bar_icon"]?.bool { config.feedback.menuBarIcon = icon }
        }

        return config
    }

    private func generateTOML(from config: Config) -> String {
        var toml = """
        [model]
        name = "\(config.model.name)"
        # api_key = "env:OPENAI_API_KEY"  # Or set OPENAI_API_KEY environment variable
        # language = "en"  # Optional: force language (omit for auto-detect)
        """

        if let language = config.model.language {
            toml += "\nlanguage = \"\(language)\""
        }

        toml += """

        
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

        return toml
    }

    private func resolveEnvValue(_ value: String) -> String {
        if value.hasPrefix("env:") {
            let envName = String(value.dropFirst(4))
            return ProcessInfo.processInfo.environment[envName] ?? ""
        }
        return value
    }
}
