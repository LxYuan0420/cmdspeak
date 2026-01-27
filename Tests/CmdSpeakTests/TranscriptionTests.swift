import Foundation
import Testing
@testable import CmdSpeakCore

@Suite("Transcription Result Tests")
struct TranscriptionTests {
    @Test("TranscriptionResult stores values correctly")
    func testTranscriptionResult() {
        let result = TranscriptionResult(
            text: "Hello world",
            language: "en",
            duration: 1.5
        )

        #expect(result.text == "Hello world")
        #expect(result.language == "en")
        #expect(result.duration == 1.5)
    }

    @Test("TranscriptionResult with nil language")
    func testTranscriptionResultNoLanguage() {
        let result = TranscriptionResult(text: "Test", language: nil, duration: 0.5)

        #expect(result.text == "Test")
        #expect(result.language == nil)
    }

    @Test("TranscriptionResult default duration is zero")
    func testTranscriptionResultDefaultDuration() {
        let result = TranscriptionResult(text: "Quick test")

        #expect(result.duration == 0)
    }

    @Test("TranscriptionError descriptions are meaningful")
    func testTranscriptionErrorDescriptions() {
        let notInitialized = TranscriptionError.notInitialized
        #expect(notInitialized.localizedDescription.contains("not initialized"))

        let modelFailed = TranscriptionError.modelLoadFailed("Test error")
        #expect(modelFailed.localizedDescription.contains("Test error"))

        let transcribeFailed = TranscriptionError.transcriptionFailed("Network issue")
        #expect(transcribeFailed.localizedDescription.contains("Network issue"))

        let emptyAudio = TranscriptionError.emptyAudio
        #expect(emptyAudio.localizedDescription.contains("No audio"))
    }
}

@Suite("Model Load Progress Tests")
struct ModelLoadProgressTests {
    @Test("ModelLoadProgress stores values correctly")
    func testModelLoadProgressStoresValues() {
        let progress = ModelLoadProgress(
            stage: .downloading,
            progress: 0.5,
            message: "Downloading: 50 / 100 MB"
        )

        #expect(progress.stage == .downloading)
        #expect(progress.progress == 0.5)
        #expect(progress.message == "Downloading: 50 / 100 MB")
    }

    @Test("ModelLoadProgress stages are distinct")
    func testModelLoadProgressStages() {
        let stages: [ModelLoadProgress.Stage] = [
            .downloading,
            .downloaded,
            .loading,
            .compiling,
            .ready
        ]

        for i in 0..<stages.count {
            for j in 0..<stages.count {
                if i == j {
                    #expect(stages[i] == stages[j])
                } else {
                    #expect(stages[i] != stages[j])
                }
            }
        }
    }

    @Test("ModelLoadProgress with zero progress")
    func testModelLoadProgressZero() {
        let progress = ModelLoadProgress(
            stage: .loading,
            progress: 0,
            message: "Starting..."
        )

        #expect(progress.progress == 0)
        #expect(progress.stage == .loading)
    }

    @Test("ModelLoadProgress with full progress")
    func testModelLoadProgressFull() {
        let progress = ModelLoadProgress(
            stage: .ready,
            progress: 1.0,
            message: "Ready"
        )

        #expect(progress.progress == 1.0)
        #expect(progress.stage == .ready)
    }
}
