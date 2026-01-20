import Foundation
import WhisperKit

/// WhisperKit-based transcription engine for on-device inference.
public actor WhisperKitEngine: TranscriptionEngine {
    private var whisperKit: WhisperKit?
    private let modelName: String

    public nonisolated var isReady: Bool {
        false  // Can't check synchronously with actor
    }

    /// Initialize the engine with a model name.
    /// - Parameter modelName: Model to use (e.g., "large-v3-turbo", "base", "small")
    public init(modelName: String = "large-v3-turbo") {
        self.modelName = modelName
    }

    public func initialize() async throws {
        do {
            whisperKit = try await WhisperKit(model: modelName)
        } catch {
            throw TranscriptionError.modelLoadFailed(error.localizedDescription)
        }
    }

    public func transcribe(audioSamples: [Float]) async throws -> TranscriptionResult {
        guard let kit = whisperKit else {
            throw TranscriptionError.notInitialized
        }

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
        whisperKit = nil
    }
}
