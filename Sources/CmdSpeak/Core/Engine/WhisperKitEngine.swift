import Foundation
import WhisperKit

/// WhisperKit-based transcription engine for on-device inference.
public actor WhisperKitEngine: TranscriptionEngine {
    private var whisperKit: WhisperKit?
    private let modelName: String
    private let language: String?
    private let translateToEnglish: Bool
    private var _isInitialized: Bool = false

    public var isReady: Bool {
        _isInitialized
    }

    /// Initialize the engine with a model name.
    /// - Parameters:
    ///   - modelName: Model to use (e.g., "openai_whisper-base", "openai_whisper-small", "openai_whisper-large-v3-turbo")
    ///   - language: Source language (nil for auto-detect)
    ///   - translateToEnglish: If true, translate non-English speech to English
    public init(
        modelName: String = "openai_whisper-base",
        language: String? = nil,
        translateToEnglish: Bool = false
    ) {
        self.modelName = modelName
        self.language = language
        self.translateToEnglish = translateToEnglish
    }

    public func initialize() async throws {
        do {
            whisperKit = try await WhisperKit(model: modelName)
            _isInitialized = true
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

        let options = DecodingOptions(
            task: translateToEnglish ? .translate : .transcribe,
            language: language,
            usePrefillPrompt: true,
            detectLanguage: language == nil
        )

        do {
            let results = try await kit.transcribe(audioArray: audioSamples, decodeOptions: options)
            let duration = Date().timeIntervalSince(startTime)

            let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            let detectedLanguage = results.first?.language

            return TranscriptionResult(
                text: text,
                language: detectedLanguage,
                duration: duration
            )
        } catch {
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
        }
    }

    public func unload() {
        whisperKit = nil
        _isInitialized = false
    }
}
