import AVFoundation
import Testing
@testable import CmdSpeakCore

@Suite("Voice Activity Detector Tests")
struct VADTests {
    @Test("Speech start is detected on loud audio")
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

        #expect(speechStarted == true)
    }

    @Test("Speech end is detected after silence")
    func testSilenceDetection() async {
        let vad = VoiceActivityDetector(
            energyThreshold: 0.01,
            silenceDuration: 0.05,
            sampleRate: 16000
        )

        var speechEnded = false
        vad.onSpeechStart = {}
        vad.onSpeechEnd = { speechEnded = true }

        let loudBuffer = createTestBuffer(amplitude: 0.5, frameCount: 1600)
        vad.process(buffer: loudBuffer)

        for _ in 0..<10 {
            let silentBuffer = createTestBuffer(amplitude: 0.001, frameCount: 1600)
            vad.process(buffer: silentBuffer)
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(speechEnded == true)
    }

    @Test("Reset allows speech start to trigger again")
    func testReset() {
        let vad = VoiceActivityDetector()

        var speechStartCount = 0
        vad.onSpeechStart = { speechStartCount += 1 }

        let loudBuffer = createTestBuffer(amplitude: 0.5, frameCount: 1600)
        vad.process(buffer: loudBuffer)

        vad.reset()

        vad.process(buffer: loudBuffer)

        #expect(speechStartCount == 2)
    }

    @Test("Silent audio does not trigger speech start")
    func testSilentAudio() {
        let vad = VoiceActivityDetector(energyThreshold: 0.01)

        var speechStarted = false
        vad.onSpeechStart = { speechStarted = true }

        let silentBuffer = createTestBuffer(amplitude: 0.001, frameCount: 1600)
        vad.process(buffer: silentBuffer)

        #expect(speechStarted == false)
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
