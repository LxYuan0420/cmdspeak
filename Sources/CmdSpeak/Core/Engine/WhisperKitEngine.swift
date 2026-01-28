import CoreML
import Foundation
import os
import WhisperKit

/// Progress information for model loading stages.
public struct ModelLoadProgress: Sendable {
    public enum Stage: Sendable {
        case downloading
        case downloaded
        case loading
        case compiling
        case ready
    }

    public let stage: Stage
    public let progress: Double
    public let message: String

    public init(stage: Stage, progress: Double, message: String) {
        self.stage = stage
        self.progress = progress
        self.message = message
    }
}

/// WhisperKit-based transcription engine for on-device inference.
/// Uses large-v3-turbo by default for best quality/speed balance.
public actor WhisperKitEngine: TranscriptionEngine {
    private static let logger = Logger(subsystem: "com.cmdspeak", category: "whisperkit-engine")

    /// Recommended model: large-v3_turbo provides near-Large-V2 accuracy with 8x speed improvement.
    /// - 954MB download (vs 3GB for full Large-V3)
    /// - 4 decoder layers (vs 32 in Large-V3)
    /// - Optimized for Apple Silicon Neural Engine
    public static let recommendedModel = "openai_whisper-large-v3_turbo"

    private var whisperKit: WhisperKit?
    private let modelName: String
    private let language: String?
    private let translateToEnglish: Bool
    private var _isInitialized: Bool = false

    /// Callback for progress updates during initialization.
    public var onProgress: (@Sendable (ModelLoadProgress) -> Void)?

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

    /// Set the progress callback.
    public func setProgressCallback(_ callback: (@Sendable (ModelLoadProgress) -> Void)?) {
        self.onProgress = callback
    }

    public func initialize() async throws {
        try await initialize(progressCallback: nil)
    }

    /// Initialize with a progress callback for download/load progress.
    public func initialize(progressCallback: (@Sendable (ModelLoadProgress) -> Void)?) async throws {
        let callback = progressCallback ?? onProgress
        Self.logger.info("Initializing WhisperKit with model: \(self.modelName)")

        whisperKit = nil
        _isInitialized = false

        do {
            try Task.checkCancellation()
            let startTime = Date()

            callback?(ModelLoadProgress(
                stage: .downloading,
                progress: 0,
                message: "Checking model..."
            ))

            let modelFolder = try await WhisperKit.download(
                variant: modelName,
                progressCallback: { progress in
                    let fractionCompleted = progress.fractionCompleted
                    let completedMB = Double(progress.completedUnitCount) / (1024 * 1024)
                    let totalMB = Double(progress.totalUnitCount) / (1024 * 1024)

                    let message: String
                    if totalMB > 0 {
                        message = String(format: "Downloading: %.0f / %.0f MB", completedMB, totalMB)
                    } else {
                        message = "Downloading model..."
                    }

                    callback?(ModelLoadProgress(
                        stage: .downloading,
                        progress: fractionCompleted,
                        message: message
                    ))
                }
            )

            try Task.checkCancellation()

            callback?(ModelLoadProgress(
                stage: .downloaded,
                progress: 1.0,
                message: "Download complete"
            ))

            callback?(ModelLoadProgress(
                stage: .loading,
                progress: 0,
                message: "Loading model..."
            ))

            let computeOptions = ModelComputeOptions(
                melCompute: .cpuAndGPU,
                audioEncoderCompute: .cpuAndNeuralEngine,
                textDecoderCompute: .cpuAndNeuralEngine,
                prefillCompute: .cpuOnly
            )

            try Task.checkCancellation()

            callback?(ModelLoadProgress(
                stage: .compiling,
                progress: 0.5,
                message: "Compiling for Neural Engine (first run may take 2-4 min)..."
            ))

            let config = WhisperKitConfig(
                modelFolder: modelFolder.path,
                computeOptions: computeOptions,
                verbose: false,
                logLevel: .error,
                prewarm: true
            )
            whisperKit = try await WhisperKit(config)

            try Task.checkCancellation()

            let loadTime = Date().timeIntervalSince(startTime)
            Self.logger.info("Model loaded in \(String(format: "%.1f", loadTime))s")

            callback?(ModelLoadProgress(
                stage: .ready,
                progress: 1.0,
                message: String(format: "Ready (loaded in %.1fs)", loadTime)
            ))

            _isInitialized = true
        } catch is CancellationError {
            whisperKit = nil
            _isInitialized = false
            Self.logger.info("Initialization cancelled")
            throw CancellationError()
        } catch {
            whisperKit = nil
            _isInitialized = false
            Self.logger.error("Failed to load model: \(String(describing: error))")
            throw TranscriptionError.modelLoadFailed(error.localizedDescription)
        }
    }

    public func transcribe(audioSamples: [Float]) async throws -> TranscriptionResult {
        try await transcribe(audioSamples: audioSamples, progressCallback: nil)
    }

    /// Transcribe audio with streaming progress callback.
    /// The callback receives partial text as transcription progresses.
    public func transcribe(
        audioSamples: [Float],
        progressCallback: (@Sendable (String) -> Void)?
    ) async throws -> TranscriptionResult {
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
            var lastReportedText = ""

            let callback: TranscriptionCallback = progressCallback != nil ? { progress in
                let currentText = progress.text.trimmingCharacters(in: .whitespaces)
                if currentText.count > lastReportedText.count {
                    let newText = String(currentText.dropFirst(lastReportedText.count))
                    lastReportedText = currentText
                    progressCallback?(newText)
                }
                return true
            } : nil

            let results = try await kit.transcribe(audioArray: audioSamples, decodeOptions: options, callback: callback)
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
