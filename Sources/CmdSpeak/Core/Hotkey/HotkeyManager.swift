import Carbon
import Cocoa
import Foundation

/// Protocol for hotkey management.
public protocol HotkeyManaging {
    var onHotkeyTriggered: (() -> Void)? { get set }
    func start() throws
    func stop()
}

/// Manages global hotkey detection for double-tap Right Command.
public final class HotkeyManager: HotkeyManaging {
    public var onHotkeyTriggered: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isStarted = false

    private var lastRightOptionTime: Date?
    private let doubleTapInterval: TimeInterval

    /// Initialize the hotkey manager.
    /// - Parameter doubleTapInterval: Maximum time between taps (default: 0.3s)
    public init(doubleTapInterval: TimeInterval = 0.3) {
        self.doubleTapInterval = doubleTapInterval
    }

    public func start() throws {
        guard !isStarted else { return }

        if !checkAccessibilityPermission() {
            requestAccessibilityPermission()
            throw HotkeyError.accessibilityNotGranted
        }

        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw HotkeyError.tapCreationFailed
        }

        eventTap = tap

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isStarted = true
    }

    public func checkAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    public func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isStarted = false
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return nil
        }

        guard type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        let isRightOption = keyCode == 61
        let optionPressed = flags.contains(.maskAlternate)

        if isRightOption && !optionPressed {
            let now = Date()

            if let lastTime = lastRightOptionTime {
                let elapsed = now.timeIntervalSince(lastTime)
                if elapsed <= doubleTapInterval {
                    lastRightOptionTime = nil
                    onHotkeyTriggered?()
                } else {
                    lastRightOptionTime = now
                }
            } else {
                lastRightOptionTime = now
            }
        }

        return Unmanaged.passUnretained(event)
    }

    deinit {
        stop()
    }
}

public enum HotkeyError: Error, LocalizedError {
    case tapCreationFailed
    case accessibilityNotGranted

    public var errorDescription: String? {
        switch self {
        case .tapCreationFailed:
            return "Failed to create event tap"
        case .accessibilityNotGranted:
            return "Accessibility permission required. Grant permission in System Settings, then restart the app."
        }
    }
}
