import AppKit
import ApplicationServices
import AVFoundation
import Foundation
import os

/// Manages system permissions required for CmdSpeak.
/// Provides onboarding flow to guide users through permission grants.
public final class PermissionsManager: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.cmdspeak", category: "permissions")

    public static let shared = PermissionsManager()

    public enum Permission: String, CaseIterable, Sendable {
        case microphone = "Microphone"
        case accessibility = "Accessibility"
    }

    public enum PermissionStatus: Sendable {
        case granted
        case denied
        case notDetermined
    }

    public struct PermissionsState: Sendable {
        public let microphone: PermissionStatus
        public let accessibility: PermissionStatus

        public var allGranted: Bool {
            microphone == .granted && accessibility == .granted
        }

        public var missingPermissions: [Permission] {
            var missing: [Permission] = []
            if microphone != .granted { missing.append(.microphone) }
            if accessibility != .granted { missing.append(.accessibility) }
            return missing
        }
    }

    private init() {}

    /// Check current state of all permissions.
    public func checkPermissions() -> PermissionsState {
        PermissionsState(
            microphone: checkMicrophonePermission(),
            accessibility: checkAccessibilityPermission()
        )
    }

    /// Check microphone permission status.
    public func checkMicrophonePermission() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    /// Check accessibility permission status.
    public func checkAccessibilityPermission() -> PermissionStatus {
        AXIsProcessTrusted() ? .granted : .denied
    }

    /// Request microphone permission.
    /// Returns true if granted, false otherwise.
    public func requestMicrophonePermission() async -> Bool {
        let status = checkMicrophonePermission()
        if status == .granted { return true }

        Self.logger.info("Requesting microphone permission")

        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Self.logger.info("Microphone permission: \(granted ? "granted" : "denied")")
                continuation.resume(returning: granted)
            }
        }
    }

    /// Request accessibility permission (opens system prompt).
    /// Note: This triggers the system dialog but returns immediately.
    /// Use `waitForAccessibilityPermission()` to poll for grant.
    public func requestAccessibilityPermission() {
        Self.logger.info("Requesting accessibility permission")
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    /// Open System Settings to the Accessibility pane.
    public func openAccessibilitySettings() {
        Self.logger.info("Opening Accessibility settings")
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Open System Settings to the Microphone pane.
    public func openMicrophoneSettings() {
        Self.logger.info("Opening Microphone settings")
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Wait for accessibility permission to be granted (polls every 0.5s).
    /// Returns true when granted, or false after timeout.
    public func waitForAccessibilityPermission(timeout: TimeInterval = 60) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if AXIsProcessTrusted() {
                Self.logger.info("Accessibility permission granted")
                return true
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        Self.logger.warning("Accessibility permission wait timed out")
        return false
    }

    /// Run the complete onboarding flow.
    /// Returns true if all permissions granted, false otherwise.
    public func runOnboarding(
        onStatus: @escaping @Sendable (String) -> Void,
        onPermissionGranted: @escaping @Sendable (Permission) -> Void
    ) async -> Bool {
        let state = checkPermissions()

        if state.allGranted {
            onStatus("All permissions already granted")
            return true
        }

        // Step 1: Microphone
        if state.microphone != .granted {
            onStatus("Requesting microphone permission...")

            let granted = await requestMicrophonePermission()
            if granted {
                onPermissionGranted(.microphone)
            } else {
                onStatus("Microphone permission denied. Opening Settings...")
                openMicrophoneSettings()
                return false
            }
        } else {
            onPermissionGranted(.microphone)
        }

        // Step 2: Accessibility
        if state.accessibility != .granted {
            onStatus("Requesting accessibility permission...")
            onStatus("Please enable CmdSpeak in the dialog or System Settings")

            requestAccessibilityPermission()

            let granted = await waitForAccessibilityPermission(timeout: 120)
            if granted {
                onPermissionGranted(.accessibility)
            } else {
                onStatus("Accessibility permission not granted. Opening Settings...")
                openAccessibilitySettings()
                return false
            }
        } else {
            onPermissionGranted(.accessibility)
        }

        return true
    }

    /// Get user-friendly instructions for a permission.
    public func instructions(for permission: Permission) -> String {
        switch permission {
        case .microphone:
            return """
            Microphone Permission Required

            CmdSpeak needs microphone access to capture your voice for transcription.

            To grant permission:
            1. A system dialog will appear - click "OK" to allow
            2. Or: System Settings → Privacy & Security → Microphone → Enable CmdSpeak
            """

        case .accessibility:
            return """
            Accessibility Permission Required

            CmdSpeak needs accessibility access to:
            • Detect the ⌥⌥ hotkey globally
            • Inject transcribed text at your cursor

            To grant permission:
            1. A system dialog will appear - click "Open System Settings"
            2. In Privacy & Security → Accessibility, enable CmdSpeak
            3. You may need to unlock the settings (click the lock icon)
            """
        }
    }

    /// Get the System Settings URL for a permission.
    public func settingsURL(for permission: Permission) -> URL? {
        switch permission {
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
    }
}
