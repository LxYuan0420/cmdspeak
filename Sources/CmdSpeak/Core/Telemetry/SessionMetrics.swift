import Foundation
import os

/// Metrics collected during a transcription session.
public struct SessionMetrics: Sendable {
    public let sessionID: UUID
    public let startTime: Date
    public let endTime: Date
    public let connectionLatencyMs: Int
    public let firstTranscriptLatencyMs: Int?
    public let totalAudioBuffersSent: Int
    public let droppedAudioBuffers: Int
    public let reconnectAttempts: Int
    public let reconnectSuccesses: Int
    public let transcribedCharacters: Int
    public let disconnectReason: DisconnectReason

    public var durationMs: Int {
        Int(endTime.timeIntervalSince(startTime) * 1000)
    }

    public var dropRate: Double {
        guard totalAudioBuffersSent + droppedAudioBuffers > 0 else { return 0 }
        return Double(droppedAudioBuffers) / Double(totalAudioBuffersSent + droppedAudioBuffers)
    }
}

/// Reason for session disconnection.
public enum DisconnectReason: Sendable, Equatable {
    case userInitiated
    case silenceTimeout
    case connectionLost
    case connectionTimeout
    case fatalError(String)
    case reconnectFailed
    case cancelled
}

/// Collects metrics during a session.
@MainActor
public final class SessionMetricsCollector {
    private static let logger = Logger(subsystem: "com.cmdspeak", category: "telemetry")

    private let sessionID: UUID
    private let startTime: Date
    private var connectionStartTime: Date?
    private var connectionLatencyMs: Int = 0
    private var firstTranscriptTime: Date?
    private var firstTranscriptLatencyMs: Int?

    private var totalAudioBuffersSent: Int = 0
    private var droppedAudioBuffers: Int = 0
    private var reconnectAttempts: Int = 0
    private var reconnectSuccesses: Int = 0
    private var transcribedCharacters: Int = 0
    private var disconnectReason: DisconnectReason = .userInitiated

    public init(sessionID: UUID) {
        self.sessionID = sessionID
        self.startTime = Date()
        Self.logger.info("Session \(sessionID.uuidString.prefix(8)) started")
    }

    public func recordConnectionStart() {
        connectionStartTime = Date()
    }

    public func recordConnectionEstablished() {
        if let start = connectionStartTime {
            connectionLatencyMs = Int(Date().timeIntervalSince(start) * 1000)
            Self.logger.debug("Connection latency: \(self.connectionLatencyMs)ms")
        }
    }

    public func recordAudioBufferSent() {
        totalAudioBuffersSent += 1
    }

    public func recordAudioBufferDropped() {
        droppedAudioBuffers += 1
    }

    public func recordTranscription(characters: Int) {
        if firstTranscriptTime == nil {
            firstTranscriptTime = Date()
            if let connStart = connectionStartTime {
                firstTranscriptLatencyMs = Int(Date().timeIntervalSince(connStart) * 1000)
                Self.logger.debug("First transcript latency: \(self.firstTranscriptLatencyMs!)ms")
            }
        }
        transcribedCharacters += characters
    }

    public func recordReconnectAttempt() {
        reconnectAttempts += 1
    }

    public func recordReconnectSuccess() {
        reconnectSuccesses += 1
    }

    public func recordDisconnect(reason: DisconnectReason) {
        disconnectReason = reason
    }

    public func finalize() -> SessionMetrics {
        let endTime = Date()
        let metrics = SessionMetrics(
            sessionID: sessionID,
            startTime: startTime,
            endTime: endTime,
            connectionLatencyMs: connectionLatencyMs,
            firstTranscriptLatencyMs: firstTranscriptLatencyMs,
            totalAudioBuffersSent: totalAudioBuffersSent,
            droppedAudioBuffers: droppedAudioBuffers,
            reconnectAttempts: reconnectAttempts,
            reconnectSuccesses: reconnectSuccesses,
            transcribedCharacters: transcribedCharacters,
            disconnectReason: disconnectReason
        )

        logMetrics(metrics)
        return metrics
    }

    private func logMetrics(_ metrics: SessionMetrics) {
        let sessionPrefix = String(metrics.sessionID.uuidString.prefix(8))
        let firstTxLatency = metrics.firstTranscriptLatencyMs.map { "\($0)ms" } ?? "n/a"
        let dropPercent = String(format: "%.1f", metrics.dropRate * 100)

        Self.logger.info(
            "Session \(sessionPrefix) ended: duration=\(metrics.durationMs)ms, connLatency=\(metrics.connectionLatencyMs)ms, firstTxLatency=\(firstTxLatency), buffers=\(metrics.totalAudioBuffersSent), dropped=\(metrics.droppedAudioBuffers) (\(dropPercent)%), reconnects=\(metrics.reconnectAttempts)/\(metrics.reconnectSuccesses), chars=\(metrics.transcribedCharacters)"
        )
    }
}

/// Aggregates metrics across sessions for reporting.
public actor TelemetryAggregator {
    private static let logger = Logger(subsystem: "com.cmdspeak", category: "telemetry")

    public static let shared = TelemetryAggregator()

    private var sessionHistory: [SessionMetrics] = []
    private let maxHistorySize = 100

    private init() {}

    public func record(_ metrics: SessionMetrics) {
        sessionHistory.append(metrics)
        if sessionHistory.count > maxHistorySize {
            sessionHistory.removeFirst()
        }
    }

    public func getRecentSessions(count: Int = 10) -> [SessionMetrics] {
        Array(sessionHistory.suffix(count))
    }

    public func getAggregateStats() -> AggregateStats {
        guard !sessionHistory.isEmpty else {
            return AggregateStats.empty
        }

        let totalSessions = sessionHistory.count
        let avgConnectionLatency = sessionHistory.map(\.connectionLatencyMs).reduce(0, +) / totalSessions
        let avgDuration = sessionHistory.map(\.durationMs).reduce(0, +) / totalSessions
        let totalDropped = sessionHistory.map(\.droppedAudioBuffers).reduce(0, +)
        let totalSent = sessionHistory.map(\.totalAudioBuffersSent).reduce(0, +)
        let overallDropRate = totalSent > 0 ? Double(totalDropped) / Double(totalSent + totalDropped) : 0
        let totalReconnects = sessionHistory.map(\.reconnectAttempts).reduce(0, +)
        let successfulReconnects = sessionHistory.map(\.reconnectSuccesses).reduce(0, +)

        return AggregateStats(
            totalSessions: totalSessions,
            avgConnectionLatencyMs: avgConnectionLatency,
            avgSessionDurationMs: avgDuration,
            overallDropRate: overallDropRate,
            totalReconnectAttempts: totalReconnects,
            successfulReconnects: successfulReconnects
        )
    }

    public func clear() {
        sessionHistory.removeAll()
    }
}

public struct AggregateStats: Sendable {
    public let totalSessions: Int
    public let avgConnectionLatencyMs: Int
    public let avgSessionDurationMs: Int
    public let overallDropRate: Double
    public let totalReconnectAttempts: Int
    public let successfulReconnects: Int

    public static let empty = AggregateStats(
        totalSessions: 0,
        avgConnectionLatencyMs: 0,
        avgSessionDurationMs: 0,
        overallDropRate: 0,
        totalReconnectAttempts: 0,
        successfulReconnects: 0
    )
}
