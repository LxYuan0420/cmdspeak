import Foundation
import os
import WhisperKit

/// WhisperKit-based transcription engine for on-device inference.
/// Uses large-v3-turbo by default for best quality/speed balance.
public actor WhisperKitEngine: TranscriptionEngine {
    private static let logger = Logger(subsystem: "com.cmdspeak", category: "whisperkit-engine")

    /// Recommended model: large-v3-turbo provides near-Large-V2 accuracy with 8x speed improvement.
    /// - 809MB download (vs 3GB for full Large-V3)
    /// - 4 decoder layers (vs 32 in Large-V3)
    /// - Optimized for Apple Silicon Neural Engine
    public static let recommendedModel = "openai_whisper-large-v3-turbo"

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
    ///   - modelName: Model to use. Default is large-v3-turbo for best quality.
    ///   - language: Source language (nil for auto-detect, recommended)
    ///   - translateToEnglish: If true, translate non-English speech to English
    public init(
        modelName: String = WhisperKitEngine.recommendedModel,
        language: String? = nil,
        translateToEnglish: Bool = false
    ) {
        self.modelName = modelName
        self.language = language
        self.translateToEnglish = translateToEnglish
    }

    public func initialize() async throws {
        Self.logger.info("Initializing WhisperKit with model: \(self.modelName)")

        do {
            let startTime = Date()
            whisperKit = try await WhisperKit(model: modelName)
            let loadTime = Date().timeIntervalSince(startTime)
            Self.logger.info("Model loaded in \(String(format: "%.1f", loadTime))s")
            _isInitialized = true
        } catch {
            Self.logger.error("Failed to load model: \(error.localizedDescription)")
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
        let audioDuration = Double(audioSamples.count) / 16000.0

        let options = DecodingOptions(
            task: translateToEnglish ? .translate : .transcribe,
            language: language,
            usePrefillPrompt: true,
            detectLanguage: language == nil
        )

        do {
            let results = try await kit.transcribe(audioArray: audioSamples, decodeOptions: options)
            let processingTime = Date().timeIntervalSince(startTime)
            let rtf = processingTime / audioDuration

            let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            let detectedLanguage = results.first?.language

            Self.logger.info(
                "Transcribed \(String(format: "%.1f", audioDuration))s audio in \(String(format: "%.2f", processingTime))s (RTF: \(String(format: "%.2f", rtf)))"
            )

            return TranscriptionResult(
                text: text,
                language: detectedLanguage,
                duration: processingTime
            )
        } catch {
            Self.logger.error("Transcription failed: \(error.localizedDescription)")
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
        }
    }

    public func unload() {
        Self.logger.info("Unloading WhisperKit model")
        whisperKit = nil
        _isInitialized = false
    }
}
