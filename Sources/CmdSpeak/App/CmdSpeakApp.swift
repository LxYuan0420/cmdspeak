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
    @Published var statusText = "Initializing..."
    @Published var errorMessage: String?
    @Published var lastTranscription: String = ""

    private var openAIController: OpenAIRealtimeController?

    var menuBarIcon: String {
        if !isReady {
            return "ellipsis.circle"
        } else if isListening {
            return "mic.circle.fill"
        } else {
            return "mic.circle"
        }
    }

    init() {
        Task {
            await initializeController()
        }
    }

    private func initializeController() async {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !apiKey.isEmpty else {
            statusText = "OPENAI_API_KEY not set"
            errorMessage = "Set OPENAI_API_KEY environment variable"
            return
        }

        do {
            var config = try ConfigManager.shared.load()
            config.model.type = "openai-realtime"
            config.model.apiKey = apiKey
            if config.model.name.isEmpty || config.model.name.hasPrefix("openai_whisper") {
                config.model.name = "gpt-4o-transcribe"
            }

            let controller = OpenAIRealtimeController(config: config)
            self.openAIController = controller

            controller.onStateChange = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .idle:
                        self?.isListening = false
                        self?.statusText = "Ready (⌥⌥ to start)"
                    case .connecting:
                        self?.isListening = false
                        self?.statusText = "Connecting..."
                    case .listening:
                        self?.isListening = true
                        self?.statusText = "Listening..."
                    case .finalizing:
                        self?.isListening = false
                        self?.statusText = "Finalizing..."
                    case .error(let msg):
                        self?.isListening = false
                        self?.statusText = "Error"
                        self?.errorMessage = msg
                    }
                }
            }

            controller.onPartialTranscription = { [weak self] delta in
                Task { @MainActor in
                    self?.lastTranscription += delta
                }
            }

            controller.onFinalTranscription = { [weak self] text in
                Task { @MainActor in
                    self?.lastTranscription = ""
                }
            }

            try await controller.start()
            isReady = true
            statusText = "Ready (⌥⌥ to start)"
        } catch {
            errorMessage = error.localizedDescription
            statusText = "Error: \(error.localizedDescription)"
        }
    }

    func stop() {
        openAIController?.stop()
    }

    func reload() async {
        openAIController?.stop()
        isReady = false
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

            if !appState.lastTranscription.isEmpty {
                Text(appState.lastTranscription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            if let error = appState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
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

    private var statusColor: Color {
        if !appState.isReady {
            return .orange
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
