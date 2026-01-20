import ArgumentParser
import CmdSpeakCore
import Foundation

@main
struct CmdSpeakCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cmdspeak",
        abstract: "Drop-in replacement for macOS Dictation",
        version: CmdSpeakCore.version,
        subcommands: [Status.self, TestMic.self, Reload.self, Run.self],
        defaultSubcommand: Run.self
    )
}

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show current CmdSpeak status"
    )

    func run() throws {
        let config = try ConfigManager.shared.load()

        print("CmdSpeak v\(CmdSpeakCore.version)")
        print("")
        print("Configuration:")
        print("  Model: \(config.model.name) (\(config.model.type))")
        print("  Hotkey: \(config.hotkey.trigger) (\(config.hotkey.intervalMs)ms interval)")
        print("  Audio: \(config.audio.sampleRate)Hz, \(config.audio.silenceThresholdMs)ms silence threshold")
        print("  Feedback: sound=\(config.feedback.soundEnabled), icon=\(config.feedback.menuBarIcon)")
        print("")

        let injector = TextInjector()
        let hasAccessibility = injector.checkAccessibilityPermission()
        print("Permissions:")
        print("  Accessibility: \(hasAccessibility ? "✓" : "✗ (required)")")

        if !hasAccessibility {
            print("")
            print("Run 'cmdspeak' to request accessibility permission.")
        }
    }
}

struct TestMic: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test-mic",
        abstract: "Test microphone input"
    )

    @Option(name: .shortAndLong, help: "Duration in seconds")
    var duration: Int = 3

    func run() async throws {
        print("Testing microphone for \(duration) seconds...")
        print("Speak now!")
        print("")

        let audioCapture = AudioCaptureManager()
        var maxLevel: Float = 0

        audioCapture.onAudioBuffer = { buffer in
            guard let data = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)

            var sum: Float = 0
            for i in 0..<frameLength {
                sum += abs(data[i])
            }
            let avg = sum / Float(frameLength)

            if avg > maxLevel {
                maxLevel = avg
            }

            let bars = Int(avg * 100)
            let barString = String(repeating: "█", count: min(bars, 50))
            print("\r\(barString.padding(toLength: 50, withPad: " ", startingAt: 0))", terminator: "")
            fflush(stdout)
        }

        try await audioCapture.startRecording()
        try await Task.sleep(nanoseconds: UInt64(duration) * 1_000_000_000)
        audioCapture.stopRecording()

        print("")
        print("")
        print("Test complete!")
        print("Max level: \(String(format: "%.4f", maxLevel))")

        if maxLevel < 0.001 {
            print("⚠️  Very low audio level detected. Check microphone connection.")
        } else if maxLevel < 0.01 {
            print("Audio level is low but detectable.")
        } else {
            print("✓ Audio level looks good!")
        }
    }
}

struct Reload: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Reload configuration"
    )

    func run() throws {
        let config = try ConfigManager.shared.load()
        print("Configuration reloaded.")
        print("Model: \(config.model.name)")
    }
}

struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run CmdSpeak (default)"
    )

    func run() async throws {
        print("CmdSpeak v\(CmdSpeakCore.version)")
        print("Loading model...")

        let config = try ConfigManager.shared.load()
        try ConfigManager.shared.createDefaultIfNeeded()

        let controller = CmdSpeakController(config: config)

        controller.onStateChange = { state in
            switch state {
            case .idle:
                print("\r[Idle] Double-tap Right ⌘ to start dictating", terminator: "")
            case .listening:
                print("\r[Listening] Speak now...                     ", terminator: "")
            case .processing:
                print("\r[Processing] Transcribing...                 ", terminator: "")
            case .injecting:
                print("\r[Injecting] Inserting text...                ", terminator: "")
            case .error(let message):
                print("\r[Error] \(message)                           ")
            }
            fflush(stdout)
        }

        try await controller.start()

        print("Model loaded!")
        print("Double-tap Right ⌘ to start/stop dictation.")
        print("Press Ctrl+C to quit.")
        print("")

        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signalSource.setEventHandler {
            print("\nShutting down...")
            controller.stop()
            Darwin.exit(0)
        }
        signalSource.resume()
        signal(SIGINT, SIG_IGN)

        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in
            // Keep running until signal
        }
    }
}
