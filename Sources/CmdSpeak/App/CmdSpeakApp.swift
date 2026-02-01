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
    @Published var statusText = "Initializing..."
    @Published var errorMessage: String?
    @Published var errorHint: String?
    @Published var lastTranscription: String = ""
    @Published var needsPermissions = false
    @Published var permissionsState: PermissionsManager.PermissionsState?

    private var controller: OpenAIRealtimeController?

    var menuBarIcon: String {
        if !isReady {
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
            return "Grant Accessibility permission in System Settings"
        }
        if lower.contains("microphone") {
            return "Grant Microphone permission in System Settings"
        }
        return nil
    }

    init() {
        Task {
            await initializeController()
        }
    }

    private func initializeController() async {
        let state = PermissionsManager.shared.checkPermissions()
        permissionsState = state

        if !state.allGranted {
            needsPermissions = true
            statusText = "Permissions required"

            let success = await PermissionsManager.shared.runOnboarding(
                onStatus: { [weak self] message in
                    Task { @MainActor in
                        self?.statusText = message
                    }
                },
                onPermissionGranted: { [weak self] _ in
                    Task { @MainActor in
                        self?.permissionsState = PermissionsManager.shared.checkPermissions()
                    }
                }
            )

            if !success {
                errorMessage = "Permissions not granted"
                errorHint = "Grant permissions in System Settings"
                return
            }

            needsPermissions = false
            permissionsState = PermissionsManager.shared.checkPermissions()
        }

        do {
            var config = try ConfigManager.shared.load()

            guard let apiKey = config.model.apiKey ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
                  !apiKey.isEmpty else {
                statusText = "OPENAI_API_KEY not set"
                errorMessage = "Set OPENAI_API_KEY environment variable"
                return
            }

            config.model.apiKey = apiKey
            config.model.name = "gpt-4o-transcribe"

            let ctrl = OpenAIRealtimeController(config: config)
            self.controller = ctrl

            ctrl.onStateChange = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .idle:
                        self?.isListening = false
                        self?.isReconnecting = false
                        self?.isFinalizing = false
                        self?.statusText = "Ready"
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

            ctrl.onPartialTranscription = { [weak self] delta in
                Task { @MainActor in
                    self?.lastTranscription += delta
                }
            }

            ctrl.onFinalTranscription = { [weak self] _ in
                Task { @MainActor in
                    self?.lastTranscription = ""
                }
            }

            try await ctrl.start()
            isReady = true
            statusText = "Ready"
        } catch {
            errorMessage = error.localizedDescription
            statusText = "Error"
        }
    }

    func stop() {
        controller?.stop()
    }

    func reload() async {
        controller?.stop()
        controller = nil
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

            if appState.needsPermissions, let state = appState.permissionsState {
                permissionsView(state: state)
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
                        Text(hint)
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

            if appState.needsPermissions {
                Button("Open Accessibility Settings") {
                    PermissionsManager.shared.openAccessibilitySettings()
                }

                Button("Open Microphone Settings") {
                    PermissionsManager.shared.openMicrophoneSettings()
                }

                Divider()
            }

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
    private func permissionsView(state: PermissionsManager.PermissionsState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: state.microphone == .granted ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundColor(state.microphone == .granted ? .green : .red)
                Text("Microphone")
                    .font(.caption)
            }
            HStack(spacing: 4) {
                Image(systemName: state.accessibility == .granted ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundColor(state.accessibility == .granted ? .green : .red)
                Text("Accessibility")
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private var transcriptionPreview: some View {
        if appState.lastTranscription.isEmpty {
            Text(appState.isListening ? "Listening..." : "Processing...")
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()
        } else {
            Text(appState.lastTranscription)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(3)
        }
    }

    private var statusColor: Color {
        if !appState.isReady {
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
                Text("Double-tap Right Option to start/stop dictation.")
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
