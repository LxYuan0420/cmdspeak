import Foundation
import Testing
@testable import CmdSpeakCore

@Suite("Session Metrics Tests")
struct SessionMetricsTests {

    @Test("SessionMetrics calculates duration correctly")
    func testDurationCalculation() {
        let start = Date()
        let end = start.addingTimeInterval(5.5)

        let metrics = SessionMetrics(
            sessionID: UUID(),
            startTime: start,
            endTime: end,
            connectionLatencyMs: 100,
            firstTranscriptLatencyMs: 500,
            totalAudioBuffersSent: 100,
            droppedAudioBuffers: 5,
            reconnectAttempts: 0,
            reconnectSuccesses: 0,
            transcribedCharacters: 50,
            disconnectReason: .userInitiated
        )

        #expect(metrics.durationMs == 5500)
    }

    @Test("SessionMetrics calculates drop rate correctly")
    func testDropRateCalculation() {
        let metrics = SessionMetrics(
            sessionID: UUID(),
            startTime: Date(),
            endTime: Date(),
            connectionLatencyMs: 100,
            firstTranscriptLatencyMs: nil,
            totalAudioBuffersSent: 90,
            droppedAudioBuffers: 10,
            reconnectAttempts: 0,
            reconnectSuccesses: 0,
            transcribedCharacters: 0,
            disconnectReason: .silenceTimeout
        )

        #expect(metrics.dropRate == 0.1)
    }

    @Test("SessionMetrics drop rate is zero when no buffers")
    func testDropRateZeroBuffers() {
        let metrics = SessionMetrics(
            sessionID: UUID(),
            startTime: Date(),
            endTime: Date(),
            connectionLatencyMs: 0,
            firstTranscriptLatencyMs: nil,
            totalAudioBuffersSent: 0,
            droppedAudioBuffers: 0,
            reconnectAttempts: 0,
            reconnectSuccesses: 0,
            transcribedCharacters: 0,
            disconnectReason: .cancelled
        )

        #expect(metrics.dropRate == 0)
    }

    @Test("DisconnectReason equality")
    func testDisconnectReasonEquality() {
        #expect(DisconnectReason.userInitiated == DisconnectReason.userInitiated)
        #expect(DisconnectReason.silenceTimeout == DisconnectReason.silenceTimeout)
        #expect(DisconnectReason.connectionLost != DisconnectReason.connectionTimeout)
        #expect(DisconnectReason.fatalError("A") == DisconnectReason.fatalError("A"))
        #expect(DisconnectReason.fatalError("A") != DisconnectReason.fatalError("B"))
    }
}

@Suite("Session Metrics Collector Tests")
@MainActor
struct SessionMetricsCollectorTests {

    @Test("Collector tracks connection latency")
    func testConnectionLatency() async throws {
        let collector = SessionMetricsCollector(sessionID: UUID())

        collector.recordConnectionStart()
        try await Task.sleep(nanoseconds: 50_000_000)
        collector.recordConnectionEstablished()

        let metrics = collector.finalize()
        #expect(metrics.connectionLatencyMs >= 40)
        #expect(metrics.connectionLatencyMs < 200)
    }

    @Test("Collector tracks audio buffers")
    func testAudioBufferTracking() {
        let collector = SessionMetricsCollector(sessionID: UUID())

        for _ in 0..<10 {
            collector.recordAudioBufferSent()
        }
        for _ in 0..<2 {
            collector.recordAudioBufferDropped()
        }

        let metrics = collector.finalize()
        #expect(metrics.totalAudioBuffersSent == 10)
        #expect(metrics.droppedAudioBuffers == 2)
    }

    @Test("Collector tracks transcription characters")
    func testTranscriptionTracking() {
        let collector = SessionMetricsCollector(sessionID: UUID())

        collector.recordTranscription(characters: 10)
        collector.recordTranscription(characters: 20)
        collector.recordTranscription(characters: 5)

        let metrics = collector.finalize()
        #expect(metrics.transcribedCharacters == 35)
    }

    @Test("Collector tracks reconnect attempts")
    func testReconnectTracking() {
        let collector = SessionMetricsCollector(sessionID: UUID())

        collector.recordReconnectAttempt()
        collector.recordReconnectAttempt()
        collector.recordReconnectSuccess()

        let metrics = collector.finalize()
        #expect(metrics.reconnectAttempts == 2)
        #expect(metrics.reconnectSuccesses == 1)
    }

    @Test("Collector tracks disconnect reason")
    func testDisconnectReason() {
        let collector = SessionMetricsCollector(sessionID: UUID())

        collector.recordDisconnect(reason: .silenceTimeout)

        let metrics = collector.finalize()
        #expect(metrics.disconnectReason == .silenceTimeout)
    }

    @Test("Collector records first transcript latency only once")
    func testFirstTranscriptLatency() async throws {
        let collector = SessionMetricsCollector(sessionID: UUID())

        collector.recordConnectionStart()
        try await Task.sleep(nanoseconds: 30_000_000)
        collector.recordTranscription(characters: 5)
        try await Task.sleep(nanoseconds: 50_000_000)
        collector.recordTranscription(characters: 10)

        let metrics = collector.finalize()
        #expect(metrics.firstTranscriptLatencyMs != nil)
        #expect(metrics.firstTranscriptLatencyMs! >= 20)
        #expect(metrics.firstTranscriptLatencyMs! < 100)
    }
}

@Suite("Telemetry Aggregator Tests", .serialized)
struct TelemetryAggregatorTests {

    @Test("Aggregator records and retrieves sessions")
    func testRecordAndRetrieve() async {
        let aggregator = TelemetryAggregator.shared
        await aggregator.clear()

        let metrics = SessionMetrics(
            sessionID: UUID(),
            startTime: Date(),
            endTime: Date().addingTimeInterval(5),
            connectionLatencyMs: 100,
            firstTranscriptLatencyMs: 200,
            totalAudioBuffersSent: 50,
            droppedAudioBuffers: 2,
            reconnectAttempts: 0,
            reconnectSuccesses: 0,
            transcribedCharacters: 100,
            disconnectReason: .userInitiated
        )

        await aggregator.record(metrics)

        let recent = await aggregator.getRecentSessions(count: 5)
        #expect(recent.count >= 1)
        #expect(recent.last?.sessionID == metrics.sessionID)
    }

    @Test("Aggregator calculates aggregate stats with fresh data")
    func testAggregateStats() async {
        let aggregator = TelemetryAggregator.shared
        await aggregator.clear()

        for i in 0..<3 {
            let metrics = SessionMetrics(
                sessionID: UUID(),
                startTime: Date(),
                endTime: Date().addingTimeInterval(Double(i + 1)),
                connectionLatencyMs: 100 * (i + 1),
                firstTranscriptLatencyMs: nil,
                totalAudioBuffersSent: 90,
                droppedAudioBuffers: 10,
                reconnectAttempts: i,
                reconnectSuccesses: i > 0 ? 1 : 0,
                transcribedCharacters: 50,
                disconnectReason: .userInitiated
            )
            await aggregator.record(metrics)
        }

        let stats = await aggregator.getAggregateStats()
        #expect(stats.totalSessions == 3)
        #expect(stats.avgConnectionLatencyMs == 200)
        #expect(abs(stats.overallDropRate - 0.1) < 0.01)
    }

    @Test("Empty aggregator returns empty stats")
    func testEmptyStats() async {
        let aggregator = TelemetryAggregator.shared
        await aggregator.clear()

        let stats = await aggregator.getAggregateStats()
        #expect(stats.totalSessions == 0)
        #expect(stats.avgConnectionLatencyMs == 0)
    }
}
