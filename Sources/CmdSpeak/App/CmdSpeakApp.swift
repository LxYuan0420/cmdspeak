import CmdSpeakCore
import SwiftUI

@main
struct CmdSpeakApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.menuBarIcon)
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var isListening = false
    @Published var isReady = false
    @Published var isReconnecting = false
    @Published var isFinalizing = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var statusText = "Initializing..."
    @Published var errorMessage: String?
    @Published var errorHint: String?
    @Published var lastTranscription: String = ""

    private var openAIController: OpenAIRealtimeController?
    private var localController: CmdSpeakController?
    private var modelType: String = "local"

    var menuBarIcon: String {
        if isDownloading {
            return "arrow.down.circle"
        } else if !isReady {
            return "ellipsis.circle"
        } else if isReconnecting {
            return "arrow.triangle.2.circlepath.circle"
        } else if isListening {
            return "mic.circle.fill"
        } else if isFinalizing {
            return "ellipsis.circle.fill"
        } else {
            return "mic.circle"
        }
    }

    func dismissError() {
        errorMessage = nil
        errorHint = nil
    }

    private func setError(_ message: String) {
        errorMessage = message
        errorHint = Self.recoveryHint(for: message)
    }

    private static func recoveryHint(for error: String) -> String? {
        let lower = error.lowercased()

        if lower.contains("api key") || lower.contains("unauthorized") || lower.contains("authentication") {
            return "Check OPENAI_API_KEY environment variable"
        }
        if lower.contains("quota") || lower.contains("billing") {
            return "Check your OpenAI account billing status"
        }
        if lower.contains("model") && lower.contains("not") {
            return "Update model name in ~/.config/cmdspeak/config.toml"
        }
        if lower.contains("timeout") || lower.contains("timed out") {
            return "Check your internet connection and try again"
        }
        if lower.contains("accessibility") {
            return "Grant Accessibility permission in System Settings → Privacy"
        }
        if lower.contains("microphone") {
            return "Grant Microphone permission in System Settings → Privacy"
        }
        return "Press ⌥⌥ to dismiss and try again"
    }

    init() {
        Task {
            await initializeController()
        }
    }

    private func initializeController() async {
        do {
            let config = try ConfigManager.shared.load()
            modelType = config.model.type

            if config.model.type == "openai-realtime" {
                try await initializeOpenAIController(config: config)
            } else {
                try await initializeLocalController(config: config)
            }
        } catch {
            errorMessage = error.localizedDescription
            statusText = "Error: \(error.localizedDescription)"
        }
    }

    private func initializeLocalController(config: Config) async throws {
        statusText = "Loading model..."
        isDownloading = true
        downloadProgress = 0

        defer {
            isDownloading = false
        }

        let controller = CmdSpeakController(config: config)
        self.localController = controller

        controller.onModelLoadProgress = { [weak self] progress in
            Task { @MainActor in
                self?.downloadProgress = progress.progress
                self?.statusText = progress.message
            }
        }

        controller.onPartialTranscription = { [weak self] delta in
            Task { @MainActor in
                self?.lastTranscription += delta
            }
        }

        controller.onFinalTranscription = { [weak self] _ in
            Task { @MainActor in
                self?.lastTranscription = ""
            }
        }

        controller.onStateChange = { [weak self] state in
            switch state {
            case .idle:
                self?.isListening = false
                self?.isFinalizing = false
                self?.statusText = "Ready (⌥⌥ to start)"
                self?.lastTranscription = ""
            case .listening:
                self?.isListening = true
                self?.isFinalizing = false
                self?.statusText = "Listening..."
            case .processing:
                self?.isListening = false
                self?.isFinalizing = true
                self?.statusText = "Processing..."
            case .injecting:
                self?.isFinalizing = true
                self?.statusText = "Injecting..."
            case .error(let msg):
                self?.isListening = false
                self?.isFinalizing = false
                self?.statusText = "Error"
                self?.setError(msg)
            }
        }

        try await controller.start()
        isDownloading = false
        isReady = true
        statusText = "Ready (⌥⌥ to start)"
    }

    private func initializeOpenAIController(config: Config) async throws {
        var mutableConfig = config

        guard let apiKey = mutableConfig.model.apiKey ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
              !apiKey.isEmpty else {
            statusText = "OPENAI_API_KEY not set"
            errorMessage = "Set OPENAI_API_KEY environment variable"
            return
        }

        mutableConfig.model.apiKey = apiKey
        if mutableConfig.model.name.isEmpty || mutableConfig.model.name.hasPrefix("openai_whisper") {
            mutableConfig.model.name = "gpt-4o-transcribe"
        }

        let controller = OpenAIRealtimeController(config: mutableConfig)
        self.openAIController = controller

        controller.onStateChange = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .idle:
                    self?.isListening = false
                    self?.isReconnecting = false
                    self?.isFinalizing = false
                    self?.statusText = "Ready (⌥⌥ to start)"
                    self?.lastTranscription = ""
                case .connecting:
                    self?.isListening = false
                    self?.isReconnecting = false
                    self?.isFinalizing = false
                    self?.statusText = "Connecting..."
                    self?.errorMessage = nil
                    self?.errorHint = nil
                case .listening:
                    self?.isListening = true
                    self?.isReconnecting = false
                    self?.isFinalizing = false
                    self?.statusText = "Listening..."
                case .reconnecting(let attempt, let maxAttempts):
                    self?.isListening = false
                    self?.isReconnecting = true
                    self?.isFinalizing = false
                    self?.statusText = "Reconnecting (\(attempt)/\(maxAttempts))..."
                case .finalizing:
                    self?.isListening = false
                    self?.isReconnecting = false
                    self?.isFinalizing = true
                    self?.statusText = "Injecting..."
                case .error(let msg):
                    self?.isListening = false
                    self?.isReconnecting = false
                    self?.isFinalizing = false
                    self?.statusText = "Error"
                    self?.setError(msg)
                }
            }
        }

        controller.onPartialTranscription = { [weak self] delta in
            Task { @MainActor in
                self?.lastTranscription += delta
            }
        }

        controller.onFinalTranscription = { [weak self] _ in
            Task { @MainActor in
                self?.lastTranscription = ""
            }
        }

        try await controller.start()
        isReady = true
        statusText = "Ready (⌥⌥ to start)"
    }

    func stop() {
        openAIController?.stop()
        localController?.stop()
    }

    func reload() async {
        openAIController?.stop()
        localController?.stop()
        openAIController = nil
        localController = nil
        isReady = false
        isDownloading = false
        downloadProgress = 0
        statusText = "Reloading..."
        lastTranscription = ""
        await initializeController()
    }
}

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(appState.statusText)
                    .font(.headline)
            }

            if appState.isDownloading {
                ProgressView(value: appState.downloadProgress)
                    .progressViewStyle(.linear)
            }

            if appState.isListening || appState.isFinalizing {
                transcriptionPreview
            }

            if let error = appState.errorMessage {
                VStack(alignment: .leading, spacing: 2) {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                    if let hint = appState.errorHint {
                        Text("💡 \(hint)")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }

                Button("Dismiss Error") {
                    appState.dismissError()
                }
                .font(.caption)
            }

            Divider()

            Text("Double-tap Right Option to dictate")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            Button("Reload") {
                Task {
                    await appState.reload()
                }
            }

            Divider()

            Button("Quit CmdSpeak") {
                appState.stop()
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var transcriptionPreview: some View {
        if appState.lastTranscription.isEmpty {
            Text(appState.isListening ? "Listening..." : "Processing...")
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()
        } else {
            HStack(alignment: .top, spacing: 4) {
                Text("📝")
                    .font(.caption)
                Text(appState.lastTranscription)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(3)
            }
        }
    }

    private var statusColor: Color {
        if appState.isDownloading {
            return .cyan
        } else if !appState.isReady {
            return .orange
        } else if appState.isReconnecting {
            return .yellow
        } else if appState.isFinalizing {
            return .purple
        } else if appState.isListening {
            return .blue
        } else if appState.errorMessage != nil {
            return .red
        } else {
            return .green
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("Status") {
                Text(appState.statusText)
            }

            Section("Info") {
                Text("CmdSpeak runs as a menu bar app.")
                Text("Double-tap Right Option (⌥⌥) to start/stop dictation.")
                Text("Text is injected at your cursor position.")
            }

            Section {
                Button("Reload Configuration") {
                    Task {
                        await appState.reload()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 250)
        .padding()
    }
}
