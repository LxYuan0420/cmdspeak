import AppKit
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
        subcommands: [Status.self, Setup.self, TestMic.self, TestHotkey.self, TestOpenAI.self, Reload.self, Run.self],
        defaultSubcommand: Run.self
    )
}

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show current CmdSpeak status"
    )

    func run() throws {
        let config = try ConfigManager.shared.load()
        let permissions = PermissionsManager.shared.checkPermissions()

        print("CmdSpeak v\(CmdSpeakCore.version)")
        print("")
        print("Configuration:")
        print("  Model: gpt-4o-transcribe (OpenAI Realtime API)")
        let langStr = config.model.language ?? "auto-detect"
        print("  Language: \(langStr)")
        print("  Hotkey: \(config.hotkey.trigger) (\(config.hotkey.intervalMs)ms interval)")
        print("  Feedback: sound=\(config.feedback.soundEnabled)")
        print("")

        print("Permissions:")
        print("  Microphone: \(statusIcon(permissions.microphone))")
        print("  Accessibility: \(statusIcon(permissions.accessibility))")

        if !permissions.allGranted {
            print("")
            print("Run 'cmdspeak setup' to configure permissions.")
        }

        print("")
        print("Config file: ~/.config/cmdspeak/config.toml")
    }

    private func statusIcon(_ status: PermissionsManager.PermissionStatus) -> String {
        switch status {
        case .granted:
            return "granted"
        case .denied:
            return "denied (run 'cmdspeak setup')"
        case .notDetermined:
            return "not requested yet"
        }
    }
}

struct Setup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Setup permissions and configure CmdSpeak"
    )

    func run() async throws {
        print("CmdSpeak Setup")
        print("==============")
        print("")

        let permissions = PermissionsManager.shared

        let state = permissions.checkPermissions()
        if state.allGranted {
            print("All permissions already granted!")
            print("")
            print("You're ready to use CmdSpeak.")
            print("Run 'cmdspeak' to start dictation.")
            return
        }

        print("CmdSpeak needs two permissions to work:")
        print("")
        print("1. Microphone - to capture your voice")
        print("2. Accessibility - to detect hotkey and inject text")
        print("")

        if state.microphone != .granted {
            print("Step 1: Microphone Permission")
            print("------------------------------")

            if state.microphone == .denied {
                print("Microphone access was previously denied.")
                print("Opening System Settings...")
                permissions.openMicrophoneSettings()
                print("")
                print("Please grant microphone access in System Settings,")
                print("then run 'cmdspeak setup' again.")
                return
            }

            print("Requesting microphone access...")
            let granted = await permissions.requestMicrophonePermission()

            if granted {
                print("Microphone access granted!")
            } else {
                print("Microphone access denied.")
                print("Please grant access in System Settings > Privacy > Microphone")
                return
            }
        } else {
            print("Step 1: Microphone - already granted")
        }

        print("")

        if state.accessibility != .granted {
            print("Step 2: Accessibility Permission")
            print("---------------------------------")
            print("")
            print("CmdSpeak needs Accessibility permission to:")
            print("  - Detect the Option key double-tap")
            print("  - Inject transcribed text at the cursor")
            print("")
            print("Opening System Settings...")
            permissions.openAccessibilitySettings()
            print("")
            print("Please add CmdSpeak to the list of allowed apps,")
            print("then run 'cmdspeak setup' again to verify.")
        } else {
            print("Step 2: Accessibility - already granted")
            print("")
            print("Setup complete! Run 'cmdspeak' to start dictation.")
        }
    }
}

struct TestMic: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test-mic",
        abstract: "Test microphone access"
    )

    @Option(name: .shortAndLong, help: "Duration in seconds")
    var duration: Int = 3

    func run() async throws {
        print("Testing microphone...")

        let granted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }

        guard granted else {
            print("Microphone permission denied")
            return
        }
        print("Microphone permission granted")

        guard let device = AVCaptureDevice.default(for: .audio) else {
            print("No audio input device found")
            return
        }
        print("Device: \(device.localizedName)")

        let session = AVCaptureSession()
        session.sessionPreset = .high

        do {
            let input = try AVCaptureDeviceInput(device: device)
            session.addInput(input)

            let output = AVCaptureAudioDataOutput()
            let delegate = SimpleAudioDelegate()
            let queue = DispatchQueue(label: "test-mic", qos: .userInteractive)
            output.setSampleBufferDelegate(delegate, queue: queue)
            session.addOutput(output)

            session.startRunning()
            print("Recording for \(duration) seconds...")

            try await Task.sleep(nanoseconds: UInt64(duration) * 1_000_000_000)

            session.stopRunning()

            let samples = delegate.sampleCount
            print("")
            print("Captured \(samples) audio samples")

            if samples > 0 {
                print("Microphone test PASSED")
            } else {
                print("Microphone test FAILED: No samples captured")
            }
        } catch {
            print("Failed to setup capture: \(error.localizedDescription)")
        }
    }
}

final class SimpleAudioDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    var sampleCount = 0

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        sampleCount += CMSampleBufferGetNumSamples(sampleBuffer)
    }
}

struct TestHotkey: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test-hotkey",
        abstract: "Test double-tap Right Option hotkey"
    )

    @Option(name: .shortAndLong, help: "How long to listen for hotkey (seconds)")
    var duration: Int = 10

    func run() throws {
        print("Testing hotkey detection...")
        print("")
        print("Double-tap Right Option key within \(duration) seconds")
        print("")

        let config = try ConfigManager.shared.load()
        let hotkeyManager = HotkeyManager(
            doubleTapInterval: TimeInterval(config.hotkey.intervalMs) / 1000.0
        )

        var triggered = false
        var triggerCount = 0

        hotkeyManager.onHotkeyTriggered = {
            triggerCount += 1
            print("Hotkey triggered! (count: \(triggerCount))")
            triggered = true
        }

        do {
            try hotkeyManager.start()
        } catch {
            print("Failed to start hotkey manager: \(error.localizedDescription)")
            return
        }

        print("Listening for double-tap Right Option...")
        print("")

        let deadline = Date().addingTimeInterval(TimeInterval(duration))
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            if triggered {
                triggered = false
            }
        }

        hotkeyManager.stop()
        print("")

        if triggerCount > 0 {
            print("Test PASSED: Hotkey triggered \(triggerCount) time(s)")
        } else {
            print("Test FAILED: No hotkey detected")
            print("  Check: Is Right Option key working?")
            print("  Check: Is accessibility permission granted?")
        }
    }
}

struct TestOpenAI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test-openai",
        abstract: "Test OpenAI Realtime API transcription"
    )

    @Option(name: .shortAndLong, help: "Duration in seconds")
    var duration: Int = 5

    func run() throws {
        print("Testing OpenAI Realtime API...")

        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !apiKey.isEmpty else {
            print("OPENAI_API_KEY environment variable not set")
            return
        }
        print("API key found")

        let semaphore = DispatchSemaphore(value: 0)
        var finalTranscription: String = ""

        Task { @MainActor in
            do {
                let engine = OpenAIRealtimeEngine(apiKey: apiKey, model: "gpt-4o-transcribe")
                try await engine.initialize()
                print("Engine initialized")

                try await engine.connect()
                print("WebSocket connected")
                print("")
                print("Speak now for \(duration) seconds...")
                print("")

                await engine.setPartialTranscriptionHandler { delta in
                    print(delta, terminator: "")
                    fflush(stdout)
                }

                guard let device = AVCaptureDevice.default(for: .audio) else {
                    print("No audio device")
                    semaphore.signal()
                    return
                }

                let session = AVCaptureSession()
                session.sessionPreset = .high
                let input = try AVCaptureDeviceInput(device: device)
                session.addInput(input)

                let output = AVCaptureAudioDataOutput()
                let collector = RealtimeAudioSender(engine: engine)
                let queue = DispatchQueue(label: "test-openai-audio", qos: .userInteractive)
                output.setSampleBufferDelegate(collector, queue: queue)
                session.addOutput(output)

                session.startRunning()
                print("[Recording...]")

                try await Task.sleep(nanoseconds: UInt64(duration) * 1_000_000_000)

                session.stopRunning()
                print("")
                print("[Recording stopped]")

                try await engine.commitAudio()
                try await Task.sleep(nanoseconds: 1_000_000_000)

                finalTranscription = await engine.getTranscription()
                await engine.disconnect()
            } catch {
                print("Error: \(error.localizedDescription)")
            }
            semaphore.signal()
        }

        while semaphore.wait(timeout: .now()) == .timedOut {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }

        print("")
        print("Final transcription: \(finalTranscription)")
    }
}

final class RealtimeAudioSender: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let engine: OpenAIRealtimeEngine
    private let targetSampleRate: Double = 24000

    init(engine: OpenAIRealtimeEngine) {
        self.engine = engine
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc),
              let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return
        }

        let sourceSampleRate = asbd.pointee.mSampleRate
        let channels = asbd.pointee.mChannelsPerFrame
        let bitsPerChannel = asbd.pointee.mBitsPerChannel
        let formatFlags = asbd.pointee.mFormatFlags
        let isFloat = (formatFlags & kAudioFormatFlagIsFloat) != 0
        let isSignedInt = (formatFlags & kAudioFormatFlagIsSignedInteger) != 0

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

        guard let rawData = dataPointer else { return }

        var floatSamples: [Float] = []
        let totalSamples = frameCount * Int(channels)

        if isFloat && bitsPerChannel == 32 {
            let floatPtr = rawData.withMemoryRebound(to: Float.self, capacity: totalSamples) { $0 }
            floatSamples = Array(UnsafeBufferPointer(start: floatPtr, count: totalSamples))
        } else if isSignedInt && bitsPerChannel == 16 {
            let int16Ptr = rawData.withMemoryRebound(to: Int16.self, capacity: totalSamples) { $0 }
            floatSamples = (0..<totalSamples).map { Float(int16Ptr[$0]) / Float(Int16.max) }
        } else if isSignedInt && bitsPerChannel == 32 {
            let int32Ptr = rawData.withMemoryRebound(to: Int32.self, capacity: totalSamples) { $0 }
            floatSamples = (0..<totalSamples).map { Float(int32Ptr[$0]) / Float(Int32.max) }
        } else {
            return
        }

        if sourceSampleRate != targetSampleRate || channels > 1 {
            let ratio = sourceSampleRate / targetSampleRate
            var resampled: [Float] = []
            let outputLen = Int(Double(floatSamples.count) / ratio / Double(channels))
            for i in 0..<outputLen {
                let srcIdx = Int(Double(i) * ratio) * Int(channels)
                if srcIdx < floatSamples.count {
                    resampled.append(floatSamples[srcIdx])
                }
            }
            floatSamples = resampled
        }

        Task {
            try? await engine.sendAudio(samples: floatSamples)
        }
    }
}

struct Reload: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Reload configuration"
    )

    func run() throws {
        _ = try ConfigManager.shared.load()
        print("Configuration reloaded.")
    }
}

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run CmdSpeak (default)"
    )

    func run() throws {
        var config = try ConfigManager.shared.load()
        try ConfigManager.shared.createDefaultIfNeeded()

        let apiKey: String
        if let key = config.model.apiKey, !key.isEmpty {
            apiKey = key
        } else if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !envKey.isEmpty {
            apiKey = envKey
        } else {
            print("Error: OpenAI API key not found")
            print("Set OPENAI_API_KEY environment variable or add api_key to config.toml")
            return
        }

        config.model.apiKey = apiKey
        config.model.name = "gpt-4o-transcribe"

        let finalConfig = config
        let semaphore = DispatchSemaphore(value: 0)
        var startError: Error?

        class ControllerHolder {
            var controller: OpenAIRealtimeController?
        }
        let holder = ControllerHolder()

        Task { @MainActor in
            let ctrl = OpenAIRealtimeController(config: finalConfig)
            holder.controller = ctrl

            ctrl.onStateChange = { state in
                switch state {
                case .idle:
                    print("[Ready]")
                    fflush(stdout)
                case .connecting:
                    break
                case .listening:
                    print("", terminator: "")
                    fflush(stdout)
                case .reconnecting(let attempt, let maxAttempts):
                    print("[Reconnecting \(attempt)/\(maxAttempts)]")
                    fflush(stdout)
                case .finalizing:
                    break
                case .error(let message):
                    print("[Error] \(message)")
                    fflush(stdout)
                }
            }

            ctrl.onPartialTranscription = { delta in
                print(delta, terminator: "")
                fflush(stdout)
            }

            ctrl.onFinalTranscription = { _ in
                print("")
                fflush(stdout)
            }

            do {
                try await ctrl.start()
            } catch {
                startError = error
            }
            semaphore.signal()
        }

        while semaphore.wait(timeout: .now()) == .timedOut {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }

        if let error = startError {
            print("Error: \(error.localizedDescription)")
            return
        }

        print("CmdSpeak | ⌥⌥ to start/cancel | Ctrl+C quit")
        print("[Ready]")
        fflush(stdout)

        signal(SIGINT) { _ in
            print("\n")
            Darwin.exit(0)
        }

        while true {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }
}
