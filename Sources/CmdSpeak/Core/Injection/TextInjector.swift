import AppKit
import ApplicationServices
import Foundation

/// Protocol for text injection functionality.
public protocol TextInjecting {
    func inject(text: String) throws
    func checkAccessibilityPermission() -> Bool
    func requestAccessibilityPermission()
}

/// Injects text at the current cursor position using macOS Accessibility APIs.
public final class TextInjector: TextInjecting {
    private let useFallbackPaste: Bool

    public init(useFallbackPaste: Bool = false) {
        self.useFallbackPaste = useFallbackPaste
    }

    public func checkAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    public func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    public func inject(text: String) throws {
        guard checkAccessibilityPermission() else {
            requestAccessibilityPermission()
            throw TextInjectionError.accessibilityNotGranted
        }

        if useFallbackPaste {
            try injectViaPaste(text: text)
        } else {
            do {
                try injectViaAccessibility(text: text)
            } catch {
                try injectViaPaste(text: text)
            }
        }
    }

    private func injectViaAccessibility(text: String) throws {
        guard let focusedElement = getFocusedElement() else {
            throw TextInjectionError.noFocusedElement
        }

        let result = AXUIElementSetAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )

        if result != .success {
            let insertResult = AXUIElementSetAttributeValue(
                focusedElement,
                kAXValueAttribute as CFString,
                text as CFTypeRef
            )

            if insertResult != .success {
                throw TextInjectionError.injectionFailed
            }
        }
    }

    private func injectViaPaste(text: String) throws {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDownV = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUpV = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            throw TextInjectionError.eventCreationFailed
        }

        keyDownV.flags = .maskCommand
        keyUpV.flags = .maskCommand

        keyDownV.post(tap: .cghidEventTap)
        keyUpV.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let previous = previousContents {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
    }

    private func getFocusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedApp: CFTypeRef?
        let appResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        )

        guard appResult == .success, let app = focusedApp else {
            return nil
        }

        var focusedElement: CFTypeRef?
        let elementResult = AXUIElementCopyAttributeValue(
            app as! AXUIElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard elementResult == .success else {
            return nil
        }

        return (focusedElement as! AXUIElement)
    }
}

public enum TextInjectionError: Error, LocalizedError {
    case accessibilityNotGranted
    case noFocusedElement
    case injectionFailed
    case eventCreationFailed

    public var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted:
            return "Accessibility permission not granted"
        case .noFocusedElement:
            return "No focused text element found"
        case .injectionFailed:
            return "Failed to inject text"
        case .eventCreationFailed:
            return "Failed to create keyboard event"
        }
    }
}
