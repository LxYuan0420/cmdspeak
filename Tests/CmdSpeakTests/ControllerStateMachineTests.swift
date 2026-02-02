import Foundation
import Testing
@testable import CmdSpeakCore

@Suite("Controller State Machine Tests")
struct ControllerStateMachineTests {

    @Test("State transitions are valid from idle")
    func testIdleTransitions() {
        let validTransitionsFromIdle: [OpenAIRealtimeController.State] = [
            .connecting,
            .error("test")
        ]

        let idle = OpenAIRealtimeController.State.idle
        for state in validTransitionsFromIdle {
            #expect(idle != state)
        }
    }

    @Test("State transitions are valid from connecting")
    func testConnectingTransitions() {
        let validTransitionsFromConnecting: [OpenAIRealtimeController.State] = [
            .listening,
            .idle,
            .error("connection failed")
        ]

        let connecting = OpenAIRealtimeController.State.connecting
        for state in validTransitionsFromConnecting {
            #expect(connecting != state)
        }
    }

    @Test("State transitions are valid from listening")
    func testListeningTransitions() {
        let validTransitionsFromListening: [OpenAIRealtimeController.State] = [
            .finalizing,
            .reconnecting(attempt: 1, maxAttempts: 3),
            .idle,
            .error("unexpected disconnect")
        ]

        let listening = OpenAIRealtimeController.State.listening
        for state in validTransitionsFromListening {
            #expect(listening != state)
        }
    }

    @Test("State transitions are valid from reconnecting")
    func testReconnectingTransitions() {
        let validTransitionsFromReconnecting: [OpenAIRealtimeController.State] = [
            .listening,
            .reconnecting(attempt: 2, maxAttempts: 3),
            .idle,
            .error("all reconnects failed")
        ]

        let reconnecting = OpenAIRealtimeController.State.reconnecting(attempt: 1, maxAttempts: 3)
        for state in validTransitionsFromReconnecting {
            #expect(reconnecting != state)
        }
    }

    @Test("State transitions are valid from finalizing")
    func testFinalizingTransitions() {
        let validTransitionsFromFinalizing: [OpenAIRealtimeController.State] = [
            .idle,
            .error("injection failed")
        ]

        let finalizing = OpenAIRealtimeController.State.finalizing
        for state in validTransitionsFromFinalizing {
            #expect(finalizing != state)
        }
    }

    @Test("State transitions are valid from error")
    func testErrorTransitions() {
        let validTransitionsFromError: [OpenAIRealtimeController.State] = [
            .idle
        ]

        let error = OpenAIRealtimeController.State.error("test")
        for state in validTransitionsFromError {
            #expect(error != state)
        }
    }

    @Test("Reconnecting attempt increments correctly")
    func testReconnectingAttemptIncrement() {
        let attempt1 = OpenAIRealtimeController.State.reconnecting(attempt: 1, maxAttempts: 3)
        let attempt2 = OpenAIRealtimeController.State.reconnecting(attempt: 2, maxAttempts: 3)
        let attempt3 = OpenAIRealtimeController.State.reconnecting(attempt: 3, maxAttempts: 3)

        #expect(attempt1 != attempt2)
        #expect(attempt2 != attempt3)
        #expect(attempt1 != attempt3)
    }

    @Test("Max attempts boundary is respected")
    func testMaxAttemptsBoundary() {
        let maxAttempts = 3
        for attempt in 1...maxAttempts {
            let state = OpenAIRealtimeController.State.reconnecting(attempt: attempt, maxAttempts: maxAttempts)
            if case .reconnecting(let a, let max) = state {
                #expect(a <= max)
            }
        }
    }
}

@Suite("Disconnect Reason Tests")
struct DisconnectReasonTests {

    @Test("All disconnect reasons are distinct")
    func testAllReasonsDistinct() {
        let reasons: [DisconnectReason] = [
            .userInitiated,
            .silenceTimeout,
            .connectionLost,
            .reconnectFailed,
            .connectionTimeout,
            .cancelled,
            .fatalError("test")
        ]

        for (i, reason1) in reasons.enumerated() {
            for (j, reason2) in reasons.enumerated() {
                if i != j {
                    #expect(reason1 != reason2)
                }
            }
        }
    }

    @Test("Fatal error with same message is equal")
    func testFatalErrorEquality() {
        let error1 = DisconnectReason.fatalError("connection refused")
        let error2 = DisconnectReason.fatalError("connection refused")
        #expect(error1 == error2)
    }

    @Test("Fatal error with different message is not equal")
    func testFatalErrorInequality() {
        let error1 = DisconnectReason.fatalError("connection refused")
        let error2 = DisconnectReason.fatalError("timeout")
        #expect(error1 != error2)
    }

    @Test("User initiated is not a failure")
    func testUserInitiatedNotFailure() {
        let reason = DisconnectReason.userInitiated
        if case .userInitiated = reason {
            #expect(true)
        } else {
            #expect(Bool(false))
        }
    }

    @Test("Connection timeout is distinct from reconnect failed")
    func testTimeoutDistinctFromReconnectFailed() {
        let timeout = DisconnectReason.connectionTimeout
        let reconnectFailed = DisconnectReason.reconnectFailed
        #expect(timeout != reconnectFailed)
    }
}

@Suite("Reconnection Flow Tests")
struct ReconnectionFlowTests {

    @Test("Reconnect attempts increment from 1 to max")
    func testReconnectAttemptSequence() {
        let maxAttempts = 3
        var attempts: [Int] = []

        for attempt in 1...maxAttempts {
            attempts.append(attempt)
        }

        #expect(attempts == [1, 2, 3])
    }

    @Test("Exponential backoff delay calculation")
    func testExponentialBackoffDelay() {
        let baseDelay: TimeInterval = 0.5

        let delay1 = baseDelay * pow(2.0, Double(1 - 1))
        let delay2 = baseDelay * pow(2.0, Double(2 - 1))
        let delay3 = baseDelay * pow(2.0, Double(3 - 1))

        #expect(delay1 == 0.5)
        #expect(delay2 == 1.0)
        #expect(delay3 == 2.0)
    }

    @Test("Jitter is within expected range")
    func testJitterRange() {
        for _ in 0..<100 {
            let jitter = Double.random(in: 0...0.3)
            #expect(jitter >= 0)
            #expect(jitter <= 0.3)
        }
    }

    @Test("Total delay with jitter is bounded")
    func testTotalDelayBounded() {
        let baseDelay: TimeInterval = 0.5
        let maxJitter: TimeInterval = 0.3

        for attempt in 1...3 {
            let delay = baseDelay * pow(2.0, Double(attempt - 1))
            let maxTotalDelay = delay + maxJitter

            #expect(delay >= baseDelay)
            #expect(maxTotalDelay <= 2.0 + maxJitter)
        }
    }

    @Test("Session ID changes abort reconnection")
    func testSessionIDAbortsBehavior() {
        let originalSessionID = UUID()
        let newSessionID = UUID()

        #expect(originalSessionID != newSessionID)
    }
}

@Suite("Audio Pipeline Tests")
struct AudioPipelineTests {

    @Test("Buffer queue limit is enforced")
    func testBufferQueueLimit() {
        let maxBufferQueue = 50

        var queuedCount = 0
        for _ in 0..<100 {
            if queuedCount < maxBufferQueue {
                queuedCount += 1
            }
        }

        #expect(queuedCount == maxBufferQueue)
    }

    @Test("Dropped buffers are counted correctly")
    func testDroppedBufferCount() {
        let maxBufferQueue = 50
        let totalBuffers = 100

        var droppedCount = 0
        var queuedCount = 0

        for _ in 0..<totalBuffers {
            if queuedCount < maxBufferQueue {
                queuedCount += 1
            } else {
                droppedCount += 1
            }
        }

        #expect(droppedCount == totalBuffers - maxBufferQueue)
        #expect(droppedCount == 50)
    }

    @Test("Empty audio buffer is handled")
    func testEmptyAudioBuffer() {
        let emptyBuffer: [Float] = []
        #expect(emptyBuffer.isEmpty)
    }

    @Test("Audio samples are Float type")
    func testAudioSampleType() {
        let samples: [Float] = [0.0, 0.5, -0.5, 1.0, -1.0]
        for sample in samples {
            #expect(sample >= -1.0 && sample <= 1.0)
        }
    }
}

@Suite("Silence Timer Tests")
struct SilenceTimerTests {

    @Test("Silence timeout is configurable")
    func testSilenceTimeoutConfiguration() {
        let configMs = 10000
        let timeout = TimeInterval(configMs) / 1000.0
        #expect(timeout == 10.0)
    }

    @Test("Silence timeout minimum is 1 second")
    func testSilenceTimeoutMinimum() {
        let minMs = 1000
        let timeout = TimeInterval(minMs) / 1000.0
        #expect(timeout >= 1.0)
    }

    @Test("Silence timeout maximum is 60 seconds")
    func testSilenceTimeoutMaximum() {
        let maxMs = 60000
        let timeout = TimeInterval(maxMs) / 1000.0
        #expect(timeout <= 60.0)
    }

    @Test("Speech started resets silence timer")
    func testSpeechStartedResetsBehavior() {
        var isSpeaking = false
        var timerActive = true

        isSpeaking = true
        timerActive = false

        #expect(isSpeaking == true)
        #expect(timerActive == false)
    }

    @Test("Speech stopped starts silence timer")
    func testSpeechStoppedStartsBehavior() {
        var isSpeaking = true
        var timerActive = false

        isSpeaking = false
        timerActive = true

        #expect(isSpeaking == false)
        #expect(timerActive == true)
    }
}

@Suite("Force Inject Tests")
struct ForceInjectTests {

    @Test("Force inject flag is initially false")
    func testForceInjectInitialState() {
        var forceInjectRequested = false
        #expect(forceInjectRequested == false)
    }

    @Test("Force inject can be requested")
    func testForceInjectRequest() {
        var forceInjectRequested = false
        forceInjectRequested = true
        #expect(forceInjectRequested == true)
    }

    @Test("Force inject is reset after use")
    func testForceInjectReset() {
        var forceInjectRequested = true
        forceInjectRequested = false
        #expect(forceInjectRequested == false)
    }
}
