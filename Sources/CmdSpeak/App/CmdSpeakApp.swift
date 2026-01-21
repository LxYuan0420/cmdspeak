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
    @Published var controllerState: CmdSpeakController.State = .idle
    @Published var isModelLoaded = false
    @Published var errorMessage: String?

    private var controller: CmdSpeakController?

    var menuBarIcon: String {
        switch controllerState {
        case .idle:
            return "mic.circle"
        case .listening:
            return "mic.circle.fill"
        case .processing:
            return "ellipsis.circle"
        case .injecting:
            return "text.cursor"
        case .error:
            return "exclamationmark.circle"
        }
    }

    var statusText: String {
        switch controllerState {
        case .idle:
            return "Ready"
        case .listening:
            return "Listening..."
        case .processing:
            return "Transcribing..."
        case .injecting:
            return "Injecting text..."
        case .error(let message):
            return "Error: \(message)"
        }
    }

    init() {
        Task {
            await initializeController()
        }
    }

    private func initializeController() async {
        do {
            let config = try ConfigManager.shared.load()
            controller = CmdSpeakController(config: config)

            controller?.onStateChange = { [weak self] state in
                Task { @MainActor in
                    self?.controllerState = state
                    if case .error(let msg) = state {
                        self?.errorMessage = msg
                    }
                }
            }

            try await controller?.start()
            isModelLoaded = true
        } catch {
            errorMessage = error.localizedDescription
            controllerState = .error(error.localizedDescription)
        }
    }

    func stop() {
        controller?.stop()
    }

    func reload() async {
        controller?.stop()
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

            if !appState.isModelLoaded {
                Text("Loading model...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            Text("Double-tap Right Option to dictate")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            Button("Reload Configuration") {
                Task {
                    await appState.reload()
                }
            }

            SettingsLink {
                Text("Settings...")
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
        switch appState.controllerState {
        case .idle:
            return .green
        case .listening:
            return .blue
        case .processing:
            return .orange
        case .injecting:
            return .purple
        case .error:
            return .red
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var modelName = "large-v3-turbo"
    @State private var silenceThresholdMs = 500
    @State private var soundEnabled = true

    var body: some View {
        Form {
            Section("Model") {
                TextField("Model Name", text: $modelName)
                    .textFieldStyle(.roundedBorder)
                Text("e.g., large-v3-turbo, base, small")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Audio") {
                Stepper("Silence threshold: \(silenceThresholdMs)ms", value: $silenceThresholdMs, in: 200...2000, step: 100)
            }

            Section("Feedback") {
                Toggle("Sound feedback", isOn: $soundEnabled)
            }

            Section {
                Button("Save & Reload") {
                    saveAndReload()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 300)
        .padding()
        .onAppear {
            loadCurrentSettings()
        }
    }

    private func loadCurrentSettings() {
        if let config = try? ConfigManager.shared.load() {
            modelName = config.model.name
            silenceThresholdMs = config.audio.silenceThresholdMs
            soundEnabled = config.feedback.soundEnabled
        }
    }

    private func saveAndReload() {
        var config = (try? ConfigManager.shared.load()) ?? Config.default
        config.model.name = modelName
        config.audio.silenceThresholdMs = silenceThresholdMs
        config.feedback.soundEnabled = soundEnabled

        try? ConfigManager.shared.save(config)

        Task {
            await appState.reload()
        }
    }
}
