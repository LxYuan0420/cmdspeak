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
        subcommands: [Status.self, TestMic.self, TestHotkey.self, TestTranscribe.self, TestIntegration.self, Reload.self, Run.self],
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

        var permissionGranted = false
        let semaphore = DispatchSemaphore(value: 0)
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            permissionGranted = granted
            semaphore.signal()
        }
        semaphore.wait()

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

        delegate.lock.lock()
        let samples = delegate.samples
        delegate.lock.unlock()

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
    var samples: [Float] = []
    let lock = NSLock()

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
        var isListening = false
        var audioSamples: [Float] = []
        let audioLock = NSLock()

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
        isListening = true
        print("✓ Recording started")

        var lastLogTime = Date()
        let recordDeadline = Date().addingTimeInterval(3)
        while Date() < recordDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            if Date().timeIntervalSince(lastLogTime) >= 0.5 {
                collector.lock.lock()
                let count = collector.samples.count
                collector.lock.unlock()
                print("  [Audio] \(count) samples (\(String(format: "%.1f", Double(count) / 16000.0))s)")
                lastLogTime = Date()
            }
        }

        session.stopRunning()
        isListening = false

        collector.lock.lock()
        audioSamples = collector.samples
        collector.lock.unlock()

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

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run CmdSpeak (default)"
    )

    func run() throws {
        print("CmdSpeak v\(CmdSpeakCore.version)")
        print("Loading model...")

        let config = try ConfigManager.shared.load()
        try ConfigManager.shared.createDefaultIfNeeded()

        let engine = WhisperKitEngine(
            modelName: config.model.name,
            language: config.model.language,
            translateToEnglish: config.model.translateToEnglish
        )
        let hotkeyManager = HotkeyManager(
            doubleTapInterval: TimeInterval(config.hotkey.intervalMs) / 1000.0
        )
        let injector = TextInjector()

        var isRunning = true
        var isListening = false
        var listeningStartTime: Date?
        let minListeningDuration: TimeInterval = 0.5
        var audioCollector: AudioCollector?
        var captureSession: AVCaptureSession?

        let semaphore = DispatchSemaphore(value: 0)
        var engineReady = false
        var engineError: Error?

        Task {
            do {
                try await engine.initialize()
                engineReady = true
            } catch {
                engineError = error
            }
            semaphore.signal()
        }

        while semaphore.wait(timeout: .now()) == .timedOut {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        if let error = engineError {
            print("Error loading model: \(error.localizedDescription)")
            return
        }

        func startListening() {
            guard !isListening else { return }

            guard let device = AVCaptureDevice.default(for: .audio) else {
                print("❌ No audio device")
                return
            }

            do {
                let session = AVCaptureSession()
                session.sessionPreset = .high
                let input = try AVCaptureDeviceInput(device: device)
                session.addInput(input)

                let output = AVCaptureAudioDataOutput()
                let collector = AudioCollector()
                let queue = DispatchQueue(label: "cmdspeak-audio", qos: .userInteractive)
                output.setSampleBufferDelegate(collector, queue: queue)
                session.addOutput(output)

                session.startRunning()
                captureSession = session
                audioCollector = collector
                isListening = true
                listeningStartTime = Date()

                if config.feedback.soundEnabled {
                    NSSound(named: "Tink")?.play()
                }

                print("\n🔴 LISTENING - Speak now! (double-tap again to stop)")
                fflush(stdout)
            } catch {
                print("❌ Audio error: \(error.localizedDescription)")
            }
        }

        func stopListeningAndTranscribe() {
            guard isListening else { return }

            captureSession?.stopRunning()
            captureSession = nil
            isListening = false
            listeningStartTime = nil

            guard let collector = audioCollector else {
                print("❌ No audio collected")
                return
            }

            collector.lock.lock()
            let samples = collector.samples
            collector.lock.unlock()
            audioCollector = nil

            let durationSec = Double(samples.count) / 16000.0
            print("\n⏳ Processing \(String(format: "%.1f", durationSec))s of audio...")
            fflush(stdout)

            guard samples.count > 1600 else {
                print("❌ Too short (\(String(format: "%.1f", durationSec))s)")
                print("\n🎤 Ready - Double-tap Right Option to dictate")
                fflush(stdout)
                return
            }

            let transcribeSemaphore = DispatchSemaphore(value: 0)
            var result: String?
            var transcribeError: Error?

            Task {
                do {
                    let transcription = try await engine.transcribe(audioSamples: samples)
                    result = transcription.text
                } catch {
                    transcribeError = error
                }
                transcribeSemaphore.signal()
            }

            while transcribeSemaphore.wait(timeout: .now()) == .timedOut {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }

            if let error = transcribeError {
                print("❌ Transcription error: \(error.localizedDescription)")
            } else if let text = result, !text.isEmpty, text != "[BLANK_AUDIO]" {
                print("✅ \"\(text)\"")
                do {
                    try injector.inject(text: text)
                    if config.feedback.soundEnabled {
                        NSSound(named: "Pop")?.play()
                    }
                } catch {
                    print("❌ Injection error: \(error.localizedDescription)")
                }
            } else {
                print("⚠️ No speech detected")
            }

            print("\n🎤 Ready - Double-tap Right Option to dictate")
            fflush(stdout)
        }

        hotkeyManager.onHotkeyTriggered = {
            if isListening {
                if let startTime = listeningStartTime,
                   Date().timeIntervalSince(startTime) < minListeningDuration {
                    return
                }
                stopListeningAndTranscribe()
            } else {
                startListening()
            }
        }

        do {
            try hotkeyManager.start()
        } catch {
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

        while isRunning {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        hotkeyManager.stop()
    }
}
