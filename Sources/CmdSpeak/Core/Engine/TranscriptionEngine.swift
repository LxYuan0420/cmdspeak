import Foundation

/// Result of a transcription operation.
public struct TranscriptionResult: Sendable {
    public let text: String
    public let language: String?
    public let duration: TimeInterval

    public init(text: String, language: String? = nil, duration: TimeInterval = 0) {
        self.text = text
        self.language = language
        self.duration = duration
    }
}

/// Protocol for transcription engines.
public protocol TranscriptionEngine: AnyObject, Sendable {
    var isReady: Bool { get }

    func initialize() async throws
    func transcribe(audioSamples: [Float]) async throws -> TranscriptionResult
    func unload()
}

/// Errors that can occur during transcription.
public enum TranscriptionError: Error, LocalizedError {
    case notInitialized
    case modelLoadFailed(String)
    case transcriptionFailed(String)
    case emptyAudio

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Transcription engine not initialized"
        case .modelLoadFailed(let message):
            return "Failed to load model: \(message)"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .emptyAudio:
            return "No audio data provided"
        }
    }
}
