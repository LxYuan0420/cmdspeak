import Foundation
import WhisperKit

/// WhisperKit-based transcription engine for on-device inference.
public final class WhisperKitEngine: TranscriptionEngine, @unchecked Sendable {
    private var whisperKit: WhisperKit?
    private let modelName: String
    private let lock = NSLock()

    public var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return whisperKit != nil
    }

    /// Initialize the engine with a model name.
    /// - Parameter modelName: Model to use (e.g., "large-v3-turbo", "base", "small")
    public init(modelName: String = "large-v3-turbo") {
        self.modelName = modelName
    }

    public func initialize() async throws {
        do {
            let kit = try await WhisperKit(model: modelName)
            lock.lock()
            whisperKit = kit
            lock.unlock()
        } catch {
            throw TranscriptionError.modelLoadFailed(error.localizedDescription)
        }
    }

    public func transcribe(audioSamples: [Float]) async throws -> TranscriptionResult {
        lock.lock()
        guard let kit = whisperKit else {
            lock.unlock()
            throw TranscriptionError.notInitialized
        }
        lock.unlock()

        guard !audioSamples.isEmpty else {
            throw TranscriptionError.emptyAudio
        }

        let startTime = Date()

        do {
            let results = try await kit.transcribe(audioArray: audioSamples)
            let duration = Date().timeIntervalSince(startTime)

            let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            let language = results.first?.language

            return TranscriptionResult(
                text: text,
                language: language,
                duration: duration
            )
        } catch {
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
        }
    }

    public func unload() {
        lock.lock()
        whisperKit = nil
        lock.unlock()
    }
}
