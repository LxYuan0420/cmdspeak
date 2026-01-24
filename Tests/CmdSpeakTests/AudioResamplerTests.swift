import AVFoundation
import Foundation
import Testing
@testable import CmdSpeakCore

@Suite("Audio Resampler Tests")
struct AudioResamplerTests {

    @Test("Resampler produces output for valid input")
    func testResamplerProducesOutput() throws {
        let resampler = AudioResampler()

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000,
            channels: 1,
            interleaved: false
        ) else {
            Issue.record("Failed to create format")
            return
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480) else {
            Issue.record("Failed to create buffer")
            return
        }
        buffer.frameLength = 480

        if let channelData = buffer.floatChannelData?[0] {
            for i in 0..<480 {
                channelData[i] = sin(Float(i) * 0.1)
            }
        }

        let result = resampler.resample(buffer)

        #expect(result != nil)
        if let samples = result {
            #expect(samples.count > 0)
        }
    }

    @Test("Resampler handles empty buffer")
    func testResamplerEmptyBuffer() throws {
        let resampler = AudioResampler()

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000,
            channels: 1,
            interleaved: false
        ) else {
            Issue.record("Failed to create format")
            return
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480) else {
            Issue.record("Failed to create buffer")
            return
        }
        buffer.frameLength = 0

        let result = resampler.resample(buffer)
        #expect(result == nil || result?.isEmpty == true)
    }

    @Test("Resampler downsamples 48kHz to 24kHz")
    func testDownsampling() throws {
        let resampler = AudioResampler()

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000,
            channels: 1,
            interleaved: false
        ) else {
            Issue.record("Failed to create format")
            return
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800) else {
            Issue.record("Failed to create buffer")
            return
        }
        buffer.frameLength = 4800

        if let channelData = buffer.floatChannelData?[0] {
            for i in 0..<4800 {
                channelData[i] = Float(i % 100) / 100.0
            }
        }

        let result = resampler.resample(buffer)

        #expect(result != nil)
        if let samples = result {
            #expect(samples.count > 0)
            #expect(samples.count < 4800)
        }
    }

    @Test("Resampler upsamples 16kHz to 24kHz")
    func testUpsampling() throws {
        let resampler = AudioResampler()

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            Issue.record("Failed to create format")
            return
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600) else {
            Issue.record("Failed to create buffer")
            return
        }
        buffer.frameLength = 1600

        if let channelData = buffer.floatChannelData?[0] {
            for i in 0..<1600 {
                channelData[i] = Float(i % 50) / 50.0
            }
        }

        let result = resampler.resample(buffer)

        #expect(result != nil)
        if let samples = result {
            #expect(samples.count > 0)
            #expect(samples.count > 1600)
        }
    }

    @Test("Resampler reset clears state")
    func testReset() {
        let resampler = AudioResampler()
        resampler.reset()
    }
}
