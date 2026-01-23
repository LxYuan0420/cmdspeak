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
        subcommands: [Status.self, TestMic.self, TestHotkey.self, TestTranscribe.self, TestIntegration.self, TestOpenAI.self, Reload.self, Run.self, RunOpenAI.self],
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
        let langStr = config.model.language ?? "auto-detect"
        let translateStr = config.model.translateToEnglish ? " → English" : ""
        print("  Language: \(langStr)\(translateStr)")
        print("  Hotkey: \(config.hotkey.trigger) (\(config.hotkey.intervalMs)ms interval)")
        print("  Feedback: sound=\(config.feedback.soundEnabled)")
        print("")

        let injector = TextInjector()
        let hasAccessibility = injector.checkAccessibilityPermission()
        print("Permissions:")
        print("  Accessibility: \(hasAccessibility ? "✓ granted" : "✗ not granted (required)")")

        if !hasAccessibility {
            print("")
            print("Run 'cmdspeak' to request accessibility permission.")
        }

        print("")
        print("Config file: ~/.config/cmdspeak/config.toml")
    }
}

final class MicTestDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    var bufferCount = 0
    var maxLevel: Float = 0
    let lock = NSLock()

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        lock.lock()
        bufferCount += 1
        let currentCount = bufferCount
        lock.unlock()

        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return
        }

        let bitsPerChannel = asbd.pointee.mBitsPerChannel
        let formatFlags = asbd.pointee.mFormatFlags
        let isFloat = (formatFlags & kAudioFormatFlagIsFloat) != 0
        let isSignedInt = (formatFlags & kAudioFormatFlagIsSignedInteger) != 0

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

        guard let data = dataPointer, length > 0 else { return }

        var avg: Float = 0

        if isFloat && bitsPerChannel == 32 {
            let floatCount = length / MemoryLayout<Float>.size
            guard floatCount > 0 else { return }
            var sum: Float = 0
            let floats = UnsafeRawPointer(data).bindMemory(to: Float.self, capacity: floatCount)
            for i in 0..<floatCount {
                sum += abs(floats[i])
            }
            avg = sum / Float(floatCount)
        } else if isSignedInt && bitsPerChannel == 16 {
            let sampleCount = length / MemoryLayout<Int16>.size
            guard sampleCount > 0 else { return }
            var sum: Float = 0
            let samples = UnsafeRawPointer(data).bindMemory(to: Int16.self, capacity: sampleCount)
            for i in 0..<sampleCount {
                sum += abs(Float(samples[i]) / Float(Int16.max))
            }
            avg = sum / Float(sampleCount)
        } else if isSignedInt && bitsPerChannel == 32 {
            let sampleCount = length / MemoryLayout<Int32>.size
            guard sampleCount > 0 else { return }
            var sum: Float = 0
            let samples = UnsafeRawPointer(data).bindMemory(to: Int32.self, capacity: sampleCount)
            for i in 0..<sampleCount {
                sum += abs(Float(samples[i]) / Float(Int32.max))
            }
            avg = sum / Float(sampleCount)
        } else {
            return
        }

        lock.lock()
        if avg > maxLevel {
            maxLevel = avg
        }
        lock.unlock()

        let bars = Int(avg * 100)
        let barString = String(repeating: "|", count: min(bars, 50))
        print("\r[\(currentCount)] \(barString.padding(toLength: 50, withPad: " ", startingAt: 0))", terminator: "")
        fflush(stdout)
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

        let semaphore = DispatchSemaphore(value: 0)
        var permissionGranted = false

        AVCaptureDevice.requestAccess(for: .audio) { granted in
            permissionGranted = granted
            semaphore.signal()
        }
        semaphore.wait()

        guard permissionGranted else {
            print("✗ Microphone permission denied")
            print("Grant permission: System Settings > Privacy & Security > Microphone > Terminal")
            return
        }

        print("✓ Microphone permission granted")

        guard let device = AVCaptureDevice.default(for: .audio) else {
            print("✗ No audio device found")
            return
        }

        print("Device: \(device.localizedName)")
        print("Speak now...")
        print("")

        let session = AVCaptureSession()
        session.sessionPreset = .high

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            print("✗ Cannot add audio input")
            return
        }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        let delegate = MicTestDelegate()
        let queue = DispatchQueue(label: "mic-test", qos: .userInteractive)
        output.setSampleBufferDelegate(delegate, queue: queue)

        guard session.canAddOutput(output) else {
            print("✗ Cannot add audio output")
            return
        }
        session.addOutput(output)

        session.startRunning()

        Thread.sleep(forTimeInterval: Double(duration))

        session.stopRunning()

        delegate.lock.lock()
        let finalCount = delegate.bufferCount
        let finalLevel = delegate.maxLevel
        delegate.lock.unlock()

        print("")
        print("")
        print("Test complete.")
        print("Buffers received: \(finalCount)")
        print("Max level: \(String(format: "%.4f", finalLevel))")

        if finalCount == 0 {
            print("No audio buffers received.")
            print("Ensure Terminal has microphone permission: System Settings > Privacy & Security > Microphone")
        } else if finalLevel < 0.001 {
            print("Very low audio level. Check microphone connection.")
        } else if finalLevel < 0.01 {
            print("Audio level is low but detectable.")
        } else {
            print("Audio level looks good.")
        }
    }
}

struct TestHotkey: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test-hotkey",
        abstract: "Test hotkey detection (double-tap Right Option)"
    )

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Int = 10

    func run() throws {
        print("Testing hotkey detection...")
        print("Double-tap Right Option key within \(timeout) seconds.")
        print("")

        let config = try ConfigManager.shared.load()
        let hotkeyManager = HotkeyManager(
            doubleTapInterval: TimeInterval(config.hotkey.intervalMs) / 1000.0
        )

        var triggered = false
        var triggerCount = 0

        hotkeyManager.onHotkeyTriggered = {
            triggerCount += 1
            triggered = true
            print("✓ Hotkey triggered! (count: \(triggerCount))")
        }

        do {
            try hotkeyManager.start()
        } catch {
            print("✗ Failed to start hotkey manager: \(error.localizedDescription)")
            return
        }

        print("Hotkey manager started. Listening...")
        print("")

        let deadline = Date().addingTimeInterval(TimeInterval(timeout))

        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            if triggered {
                triggered = false
            }
        }

        hotkeyManager.stop()
        print("")

        if triggerCount > 0 {
            print("✓ Test PASSED: Hotkey triggered \(triggerCount) time(s)")
        } else {
            print("✗ Test FAILED: No hotkey detected")
            print("  Check: Is Right Option key working?")
            print("  Check: Is accessibility permission granted?")
        }
    }
}

struct TestTranscribe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test-transcribe",
        abstract: "Test model loading and transcription with mic input"
    )

    @Option(name: .shortAndLong, help: "Recording duration in seconds")
    var duration: Int = 3

    func run() async throws {
        print("Testing transcription pipeline...")

        let config = try ConfigManager.shared.load()
        print("Loading model: \(config.model.name)")

        let engine = WhisperKitEngine(
            modelName: config.model.name,
            language: config.model.language,
            translateToEnglish: config.model.translateToEnglish
        )

        let startLoad = Date()
        try await engine.initialize()
        let loadTime = Date().timeIntervalSince(startLoad)
        print("✓ Model loaded in \(String(format: "%.1f", loadTime))s")

        print("")
        print("Recording for \(duration) seconds...")
        print("Speak now!")

        let permissionGranted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }

        guard permissionGranted else {
            print("✗ Microphone permission denied")
            return
        }

        guard let device = AVCaptureDevice.default(for: .audio) else {
            print("✗ No audio device")
            return
        }

        let session = AVCaptureSession()
        session.sessionPreset = .high
        let input = try AVCaptureDeviceInput(device: device)
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        let delegate = AudioCollector()
        let queue = DispatchQueue(label: "test-transcribe", qos: .userInteractive)
        output.setSampleBufferDelegate(delegate, queue: queue)
        session.addOutput(output)

        session.startRunning()
        try await Task.sleep(nanoseconds: UInt64(duration) * 1_000_000_000)
        session.stopRunning()

        let samples = delegate.getSamples()

        let durationSec = Double(samples.count) / 16000.0
        print("")
        print("Captured \(samples.count) samples (\(String(format: "%.1f", durationSec))s)")

        guard samples.count > 1600 else {
            print("✗ Too short, need > 0.1s of audio")
            return
        }

        print("Transcribing...")
        let result = try await engine.transcribe(audioSamples: samples)

        print("")
        print("═══════════════════════════════════════")
        print("Result: \"\(result.text)\"")
        print("Time: \(String(format: "%.2f", result.duration))s")
        if let lang = result.language {
            print("Language: \(lang)")
        }
        print("═══════════════════════════════════════")
    }
}

final class AudioCollector: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private var samples: [Float] = []
    private let lock = NSLock()

    func getSamples() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    func getCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return samples.count
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return }

        let sampleRate = asbd.pointee.mSampleRate
        let channels = asbd.pointee.mChannelsPerFrame
        let bitsPerChannel = asbd.pointee.mBitsPerChannel
        let formatFlags = asbd.pointee.mFormatFlags

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        guard let data = dataPointer, length > 0 else { return }

        let isFloat = (formatFlags & kAudioFormatFlagIsFloat) != 0
        let isSignedInt = (formatFlags & kAudioFormatFlagIsSignedInteger) != 0

        var floatSamples: [Float] = []
        if isFloat && bitsPerChannel == 32 {
            let floatCount = length / MemoryLayout<Float>.size
            let floats = UnsafeRawPointer(data).bindMemory(to: Float.self, capacity: floatCount)
            for i in 0..<floatCount {
                floatSamples.append(floats[i])
            }
        } else if isSignedInt && bitsPerChannel == 16 {
            let count = length / MemoryLayout<Int16>.size
            let int16s = UnsafeRawPointer(data).bindMemory(to: Int16.self, capacity: count)
            for i in 0..<count {
                floatSamples.append(Float(int16s[i]) / Float(Int16.max))
            }
        } else if isSignedInt && bitsPerChannel == 32 {
            let count = length / MemoryLayout<Int32>.size
            let int32s = UnsafeRawPointer(data).bindMemory(to: Int32.self, capacity: count)
            for i in 0..<count {
                floatSamples.append(Float(int32s[i]) / Float(Int32.max))
            }
        }

        let targetRate = 16000.0
        if sampleRate != targetRate && sampleRate > 0 {
            let ratio = sampleRate / targetRate
            var resampled: [Float] = []
            let outputLen = Int(Double(floatSamples.count) / ratio / Double(channels))
            for i in 0..<outputLen {
                let srcIdx = Int(Double(i) * ratio) * Int(channels)
                if srcIdx < floatSamples.count {
                    resampled.append(floatSamples[srcIdx])
                }
            }
            floatSamples = resampled
        } else if channels > 1 {
            var mono: [Float] = []
            for i in stride(from: 0, to: floatSamples.count, by: Int(channels)) {
                mono.append(floatSamples[i])
            }
            floatSamples = mono
        }

        lock.lock()
        samples.append(contentsOf: floatSamples)
        lock.unlock()
    }
}

struct TestIntegration: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test-integration",
        abstract: "Test full pipeline: hotkey → audio → transcription (no run loop)"
    )

    func run() throws {
        print("═══════════════════════════════════════")
        print("Integration Test: Hotkey → Audio → Transcription")
        print("═══════════════════════════════════════")
        print("")

        let config = try ConfigManager.shared.load()
        var hotkeyTriggered = false
        var audioSamples: [Float] = []

        let hotkeyManager = HotkeyManager(
            doubleTapInterval: TimeInterval(config.hotkey.intervalMs) / 1000.0
        )

        hotkeyManager.onHotkeyTriggered = {
            print("[Test] Hotkey triggered!")
            hotkeyTriggered = true
        }

        do {
            try hotkeyManager.start()
        } catch {
            print("✗ Failed to start hotkey: \(error)")
            return
        }
        print("✓ Hotkey manager started")

        print("")
        print("Step 1: Double-tap Right Option to trigger hotkey...")

        let deadline1 = Date().addingTimeInterval(10)
        while !hotkeyTriggered && Date() < deadline1 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        guard hotkeyTriggered else {
            print("✗ Hotkey not triggered within 10s")
            hotkeyManager.stop()
            return
        }
        print("✓ Hotkey detected!")
        hotkeyTriggered = false

        print("")
        print("Step 2: Starting audio capture. Speak now for 3 seconds...")

        guard let device = AVCaptureDevice.default(for: .audio) else {
            print("✗ No audio device")
            return
        }

        let session = AVCaptureSession()
        session.sessionPreset = .high
        let input = try AVCaptureDeviceInput(device: device)
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        let collector = AudioCollector()
        let queue = DispatchQueue(label: "test-integration-audio", qos: .userInteractive)
        output.setSampleBufferDelegate(collector, queue: queue)
        session.addOutput(output)

        session.startRunning()
        print("✓ Recording started")

        var lastLogTime = Date()
        let recordDeadline = Date().addingTimeInterval(3)
        while Date() < recordDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            if Date().timeIntervalSince(lastLogTime) >= 0.5 {
                let count = collector.getCount()
                print("  [Audio] \(count) samples (\(String(format: "%.1f", Double(count) / 16000.0))s)")
                lastLogTime = Date()
            }
        }

        session.stopRunning()

        audioSamples = collector.getSamples()

        print("✓ Recording stopped: \(audioSamples.count) samples (\(String(format: "%.1f", Double(audioSamples.count) / 16000.0))s)")

        guard audioSamples.count > 1600 else {
            print("✗ Too little audio captured")
            hotkeyManager.stop()
            return
        }

        print("")
        print("Step 3: Transcribing...")

        let semaphore = DispatchSemaphore(value: 0)
        var transcriptionResult: String?
        var transcriptionError: Error?

        Task {
            do {
                let engine = WhisperKitEngine(
                    modelName: config.model.name,
                    language: config.model.language,
                    translateToEnglish: config.model.translateToEnglish
                )
                try await engine.initialize()
                let result = try await engine.transcribe(audioSamples: audioSamples)
                transcriptionResult = result.text
            } catch {
                transcriptionError = error
            }
            semaphore.signal()
        }

        while semaphore.wait(timeout: .now()) == .timedOut {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        if let error = transcriptionError {
            print("✗ Transcription failed: \(error)")
        } else if let text = transcriptionResult {
            print("✓ Transcription: \"\(text)\"")
        }

        print("")
        print("Step 4: Double-tap Right Option again to confirm hotkey still works...")

        let deadline2 = Date().addingTimeInterval(10)
        while !hotkeyTriggered && Date() < deadline2 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        if hotkeyTriggered {
            print("✓ Hotkey still working!")
        } else {
            print("⚠ Hotkey not triggered (timeout)")
        }

        hotkeyManager.stop()

        print("")
        print("═══════════════════════════════════════")
        print("Integration test complete!")
        print("═══════════════════════════════════════")
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
            print("✗ OPENAI_API_KEY environment variable not set")
            return
        }
        print("✓ API key found")

        let semaphore = DispatchSemaphore(value: 0)
        var finalTranscription: String = ""

        Task { @MainActor in
            do {
                let engine = OpenAIRealtimeEngine(apiKey: apiKey, model: "gpt-4o-transcribe")
                try await engine.initialize()
                print("✓ Engine initialized")

                try await engine.connect()
                print("✓ WebSocket connected")
                print("")
                print("Speak now for \(duration) seconds...")
                print("")

                await engine.setPartialTranscriptionHandler { delta in
                    print(delta, terminator: "")
                    fflush(stdout)
                }

                guard let device = AVCaptureDevice.default(for: .audio) else {
                    print("✗ No audio device")
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
                print("✗ Error: \(error.localizedDescription)")
            }
            semaphore.signal()
        }

        while semaphore.wait(timeout: .now()) == .timedOut {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }

        print("")
        print("═══════════════════════════════════════")
        print("Final transcription: \(finalTranscription)")
        print("═══════════════════════════════════════")
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
        guard let data = dataPointer, length > 0 else { return }

        var floatSamples = [Float](repeating: 0, count: frameCount)

        if isFloat && bitsPerChannel == 32 {
            let floatData = UnsafeRawPointer(data).bindMemory(to: Float.self, capacity: frameCount * Int(channels))
            for i in 0..<frameCount {
                floatSamples[i] = floatData[i * Int(channels)]
            }
        } else if isSignedInt && bitsPerChannel == 16 {
            let int16Data = UnsafeRawPointer(data).bindMemory(to: Int16.self, capacity: frameCount * Int(channels))
            for i in 0..<frameCount {
                floatSamples[i] = Float(int16Data[i * Int(channels)]) / Float(Int16.max)
            }
        } else if isSignedInt && bitsPerChannel == 32 {
            let int32Data = UnsafeRawPointer(data).bindMemory(to: Int32.self, capacity: frameCount * Int(channels))
            for i in 0..<frameCount {
                floatSamples[i] = Float(int32Data[i * Int(channels)]) / Float(Int32.max)
            }
        } else {
            return
        }

        let ratio = sourceSampleRate / targetSampleRate
        let outputLength = Int(Double(frameCount) / ratio)
        guard outputLength > 0 else { return }

        var resampled = [Float](repeating: 0, count: outputLength)
        for i in 0..<outputLength {
            let srcIndex = Int(Double(i) * ratio)
            if srcIndex < frameCount {
                resampled[i] = floatSamples[srcIndex]
            }
        }

        Task {
            try? await engine.sendAudio(samples: resampled)
        }
    }
}

struct RunOpenAI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run-openai",
        abstract: "Run CmdSpeak with OpenAI Realtime API"
    )

    func run() throws {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !apiKey.isEmpty else {
            print("Error: OPENAI_API_KEY environment variable not set")
            return
        }

        var config = try ConfigManager.shared.load()
        config.model.type = "openai-realtime"
        config.model.apiKey = apiKey
        if config.model.name.isEmpty || config.model.name.hasPrefix("openai_whisper") {
            config.model.name = "gpt-4o-transcribe"
        }

        let semaphore = DispatchSemaphore(value: 0)
        var startError: Error?

        class ControllerHolder {
            var controller: OpenAIRealtimeController?
        }
        let holder = ControllerHolder()

        Task { @MainActor in
            let ctrl = OpenAIRealtimeController(config: config)
            holder.controller = ctrl

            ctrl.onStateChange = { state in
                switch state {
                case .idle:
                    print("\n[⌥⌥ to start]")
                    fflush(stdout)
                case .connecting:
                    print("[connecting] ", terminator: "")
                    fflush(stdout)
                case .listening:
                    print("\r[listening]  ", terminator: "")
                    fflush(stdout)
                case .finalizing:
                    print(" [finalizing...]", terminator: "")
                    fflush(stdout)
                case .error(let message):
                    print("[error] \(message)")
                    fflush(stdout)
                }
            }

            ctrl.onPartialTranscription = { delta in
                print(delta, terminator: "")
                fflush(stdout)
            }

            ctrl.onFinalTranscription = { _ in
                print(" [done]")
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

        print("CmdSpeak | ⌥⌥ start → speak → ⌥⌥ stop (or 10s silence) | Ctrl+C quit")
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

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run CmdSpeak (default)"
    )

    func run() throws {
        print("CmdSpeak v\(CmdSpeakCore.version)")
        print("Loading model...")

        let config = try ConfigManager.shared.load()
        try ConfigManager.shared.createDefaultIfNeeded()

        let semaphore = DispatchSemaphore(value: 0)
        var startError: Error?

        class ControllerHolder {
            var controller: CmdSpeakController?
        }
        let holder = ControllerHolder()

        Task { @MainActor in
            let ctrl = CmdSpeakController(config: config)
            holder.controller = ctrl

            ctrl.onStateChange = { state in
                switch state {
                case .idle:
                    print("\n🎤 Ready - Double-tap Right Option to dictate")
                    fflush(stdout)
                case .listening:
                    print("\n🔴 LISTENING - Speak now! (double-tap again to stop)")
                    fflush(stdout)
                case .processing:
                    print("\n⏳ Processing...")
                    fflush(stdout)
                case .injecting:
                    break
                case .error(let message):
                    print("❌ Error: \(message)")
                    fflush(stdout)
                }
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

        let langInfo: String
        if config.model.translateToEnglish {
            langInfo = " (translate → English)"
        } else if let lang = config.model.language {
            langInfo = " (\(lang))"
        } else {
            langInfo = ""
        }

        print("✓ Ready\(langInfo)")
        print("")
        print("  Double-tap Right Option to start/stop dictation")
        print("  Ctrl+C to quit")
        print("")
        print("Tip: Disable macOS Dictation shortcut to avoid conflicts:")
        print("  System Settings → Keyboard → Dictation → Shortcut → Off")
        print("")
        print("🎤 Waiting for input...")
        fflush(stdout)

        signal(SIGINT) { _ in
            print("\nShutting down...")
            Darwin.exit(0)
        }

        dispatchMain()
    }
}
