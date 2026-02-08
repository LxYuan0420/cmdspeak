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
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
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

        var savedItems: [[(NSPasteboard.PasteboardType, Data)]] = []
        if let pasteboardItems = pasteboard.pasteboardItems {
            for item in pasteboardItems {
                var itemData: [(NSPasteboard.PasteboardType, Data)] = []
                for type in item.types {
                    if let data = item.data(forType: type) {
                        itemData.append((type, data))
                    }
                }
                if !itemData.isEmpty {
                    savedItems.append(itemData)
                }
            }
        }

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

        Thread.sleep(forTimeInterval: 0.1)

        if !savedItems.isEmpty {
            pasteboard.clearContents()
            for itemData in savedItems {
                let newItem = NSPasteboardItem()
                for (type, data) in itemData {
                    newItem.setData(data, forType: type)
                }
                pasteboard.writeObjects([newItem])
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

        guard appResult == .success,
              let app = focusedApp,
              CFGetTypeID(app) == AXUIElementGetTypeID() else {
            return nil
        }

        let appElement = app as! AXUIElement
        var focusedElement: CFTypeRef?
        let elementResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard elementResult == .success,
              let element = focusedElement,
              CFGetTypeID(element) == AXUIElementGetTypeID() else {
            return nil
        }

        return (element as! AXUIElement)
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
