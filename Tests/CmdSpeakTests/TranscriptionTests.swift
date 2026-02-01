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
