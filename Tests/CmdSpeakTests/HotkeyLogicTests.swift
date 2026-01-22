import Foundation
import Testing

@Suite("Hotkey Double-Tap Logic Tests")
struct HotkeyLogicTests {
    @Test("Double-tap within interval triggers")
    func testDoubleTapTriggers() {
        var triggered = false
        var lastTapTime: Date?
        let interval: TimeInterval = 0.3

        func simulateTap(at time: Date) {
            if let lastTime = lastTapTime {
                let elapsed = time.timeIntervalSince(lastTime)
                if elapsed <= interval {
                    triggered = true
                    lastTapTime = nil
                } else {
                    lastTapTime = time
                }
            } else {
                lastTapTime = time
            }
        }

        let now = Date()
        simulateTap(at: now)
        simulateTap(at: now.addingTimeInterval(0.2))

        #expect(triggered == true)
    }

    @Test("Double-tap outside interval does not trigger")
    func testSlowDoubleTapDoesNotTrigger() {
        var triggered = false
        var lastTapTime: Date?
        let interval: TimeInterval = 0.3

        func simulateTap(at time: Date) {
            if let lastTime = lastTapTime {
                let elapsed = time.timeIntervalSince(lastTime)
                if elapsed <= interval {
                    triggered = true
                    lastTapTime = nil
                } else {
                    lastTapTime = time
                }
            } else {
                lastTapTime = time
            }
        }

        let now = Date()
        simulateTap(at: now)
        simulateTap(at: now.addingTimeInterval(0.5))

        #expect(triggered == false)
    }

    @Test("Single tap does not trigger")
    func testSingleTapDoesNotTrigger() {
        var triggered = false
        var lastTapTime: Date?
        let interval: TimeInterval = 0.3

        func simulateTap(at time: Date) {
            if let lastTime = lastTapTime {
                let elapsed = time.timeIntervalSince(lastTime)
                if elapsed <= interval {
                    triggered = true
                    lastTapTime = nil
                } else {
                    lastTapTime = time
                }
            } else {
                lastTapTime = time
            }
        }

        simulateTap(at: Date())

        #expect(triggered == false)
    }

    @Test("Triple tap triggers on second pair")
    func testTripleTap() {
        var triggerCount = 0
        var lastTapTime: Date?
        let interval: TimeInterval = 0.3

        func simulateTap(at time: Date) {
            if let lastTime = lastTapTime {
                let elapsed = time.timeIntervalSince(lastTime)
                if elapsed <= interval {
                    triggerCount += 1
                    lastTapTime = nil
                } else {
                    lastTapTime = time
                }
            } else {
                lastTapTime = time
            }
        }

        let now = Date()
        simulateTap(at: now)
        simulateTap(at: now.addingTimeInterval(0.1))
        simulateTap(at: now.addingTimeInterval(0.2))

        #expect(triggerCount == 1)
    }
}
