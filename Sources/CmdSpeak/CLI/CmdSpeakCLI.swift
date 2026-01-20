import ArgumentParser
import AVFoundation
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
        print("  Accessibility: \(hasAccessibility ? "granted" : "not granted (required)")")

        if !hasAccessibility {
            print("")
            print("Run 'cmdspeak' to request accessibility permission.")
        }
    }
}

struct TestMic: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test-mic",
        abstract: "Test microphone input"
    )

    @Option(name: .shortAndLong, help: "Duration in seconds")
    var duration: Int = 3

    func run() throws {
        print("Testing microphone for \(duration) seconds...")
        print("Note: Terminal.app must have microphone permission in System Settings.")
        print("Speak now...")
        print("")

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        var maxLevel: Float = 0
        var bufferCount = 0

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            bufferCount += 1
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
            let barString = String(repeating: "|", count: min(bars, 50))
            print("\r[\(bufferCount)] \(barString.padding(toLength: 50, withPad: " ", startingAt: 0))", terminator: "")
            fflush(stdout)
        }

        engine.prepare()
        try engine.start()

        Thread.sleep(forTimeInterval: TimeInterval(duration))

        inputNode.removeTap(onBus: 0)
        engine.stop()

        print("")
        print("")
        print("Test complete.")
        print("Buffers received: \(bufferCount)")
        print("Max level: \(String(format: "%.4f", maxLevel))")

        if bufferCount == 0 {
            print("No audio buffers received.")
            print("Ensure Terminal has microphone permission: System Settings > Privacy & Security > Microphone")
        } else if maxLevel < 0.001 {
            print("Very low audio level. Check microphone connection.")
        } else if maxLevel < 0.01 {
            print("Audio level is low but detectable.")
        } else {
            print("Audio level looks good.")
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

    @MainActor
    func run() async throws {
        print("CmdSpeak v\(CmdSpeakCore.version)")
        print("Loading model...")

        let config = try ConfigManager.shared.load()
        try ConfigManager.shared.createDefaultIfNeeded()

        let controller = CmdSpeakController(config: config)

        controller.onStateChange = { state in
            switch state {
            case .idle:
                print("\r[Idle] Double-tap Right Cmd to start dictating", terminator: "")
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

        do {
            try await controller.start()
        } catch {
            print("Error: \(error.localizedDescription)")
            return
        }

        print("Ready.")
        print("Double-tap Right Cmd to dictate. Ctrl+C to quit.")
        print("")
        print("Note: Disable macOS Dictation shortcut in System Settings > Keyboard > Dictation")

        signal(SIGINT) { _ in
            Darwin.exit(0)
        }

        // Keep the run loop running
        CFRunLoopRun()
    }
}
