import AVFoundation
import XCTest
@testable import CmdSpeakCore

final class VADTests: XCTestCase {
    func testSpeechDetection() {
        let vad = VoiceActivityDetector(
            energyThreshold: 0.01,
            silenceDuration: 0.1,
            sampleRate: 16000
        )

        var speechStarted = false
        vad.onSpeechStart = { speechStarted = true }

        let loudBuffer = createTestBuffer(amplitude: 0.5, frameCount: 1600)
        vad.process(buffer: loudBuffer)

        XCTAssertTrue(speechStarted)
    }

    func testSilenceDetection() {
        let expectation = XCTestExpectation(description: "Speech end detected")

        let vad = VoiceActivityDetector(
            energyThreshold: 0.01,
            silenceDuration: 0.05,
            sampleRate: 16000
        )

        vad.onSpeechStart = {}
        vad.onSpeechEnd = { expectation.fulfill() }

        let loudBuffer = createTestBuffer(amplitude: 0.5, frameCount: 1600)
        vad.process(buffer: loudBuffer)

        for _ in 0..<10 {
            let silentBuffer = createTestBuffer(amplitude: 0.001, frameCount: 1600)
            vad.process(buffer: silentBuffer)
            Thread.sleep(forTimeInterval: 0.02)
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testReset() {
        let vad = VoiceActivityDetector()

        var speechStartCount = 0
        vad.onSpeechStart = { speechStartCount += 1 }

        let loudBuffer = createTestBuffer(amplitude: 0.5, frameCount: 1600)
        vad.process(buffer: loudBuffer)

        vad.reset()

        vad.process(buffer: loudBuffer)

        XCTAssertEqual(speechStartCount, 2)
    }

    private func createTestBuffer(amplitude: Float, frameCount: AVAudioFrameCount) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        if let channelData = buffer.floatChannelData?[0] {
            for i in 0..<Int(frameCount) {
                channelData[i] = amplitude * sin(Float(i) * 0.1)
            }
        }

        return buffer
    }
}
