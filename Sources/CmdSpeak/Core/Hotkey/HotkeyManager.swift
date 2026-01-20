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

    private var lastRightCmdTime: Date?
    private let doubleTapInterval: TimeInterval

    /// Initialize the hotkey manager.
    /// - Parameter doubleTapInterval: Maximum time between taps (default: 0.3s)
    public init(doubleTapInterval: TimeInterval = 0.3) {
        self.doubleTapInterval = doubleTapInterval
    }

    public func start() throws {
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
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw HotkeyError.tapCreationFailed
        }

        eventTap = tap

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
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
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .flagsChanged else {
            return Unmanaged.passRetained(event)
        }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        let isRightCmd = keyCode == 54
        let cmdPressed = flags.contains(.maskCommand)

        if isRightCmd && !cmdPressed {
            let now = Date()

            if let lastTime = lastRightCmdTime,
               now.timeIntervalSince(lastTime) <= doubleTapInterval {
                lastRightCmdTime = nil
                DispatchQueue.main.async { [weak self] in
                    self?.onHotkeyTriggered?()
                }
            } else {
                lastRightCmdTime = now
            }
        }

        return Unmanaged.passRetained(event)
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
