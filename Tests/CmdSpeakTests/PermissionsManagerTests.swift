import Foundation
import Testing
@testable import CmdSpeakCore

@Suite("Permissions Manager Tests")
struct PermissionsManagerTests {

    @Test("PermissionsState correctly identifies all granted")
    func testAllGranted() {
        let state = PermissionsManager.PermissionsState(
            microphone: .granted,
            accessibility: .granted
        )
        #expect(state.allGranted == true)
        #expect(state.missingPermissions.isEmpty)
    }

    @Test("PermissionsState correctly identifies missing microphone")
    func testMissingMicrophone() {
        let state = PermissionsManager.PermissionsState(
            microphone: .denied,
            accessibility: .granted
        )
        #expect(state.allGranted == false)
        #expect(state.missingPermissions.contains(.microphone))
        #expect(!state.missingPermissions.contains(.accessibility))
    }

    @Test("PermissionsState correctly identifies missing accessibility")
    func testMissingAccessibility() {
        let state = PermissionsManager.PermissionsState(
            microphone: .granted,
            accessibility: .denied
        )
        #expect(state.allGranted == false)
        #expect(!state.missingPermissions.contains(.microphone))
        #expect(state.missingPermissions.contains(.accessibility))
    }

    @Test("PermissionsState correctly identifies both missing")
    func testBothMissing() {
        let state = PermissionsManager.PermissionsState(
            microphone: .denied,
            accessibility: .denied
        )
        #expect(state.allGranted == false)
        #expect(state.missingPermissions.count == 2)
        #expect(state.missingPermissions.contains(.microphone))
        #expect(state.missingPermissions.contains(.accessibility))
    }

    @Test("PermissionsState handles notDetermined as not granted")
    func testNotDetermined() {
        let state = PermissionsManager.PermissionsState(
            microphone: .notDetermined,
            accessibility: .notDetermined
        )
        #expect(state.allGranted == false)
        #expect(state.missingPermissions.count == 2)
    }

    @Test("Permission enum has correct raw values")
    func testPermissionRawValues() {
        #expect(PermissionsManager.Permission.microphone.rawValue == "Microphone")
        #expect(PermissionsManager.Permission.accessibility.rawValue == "Accessibility")
    }

    @Test("Permission enum is CaseIterable")
    func testPermissionCaseIterable() {
        let allCases = PermissionsManager.Permission.allCases
        #expect(allCases.count == 2)
        #expect(allCases.contains(.microphone))
        #expect(allCases.contains(.accessibility))
    }

    @Test("Instructions are provided for each permission")
    func testInstructions() {
        let manager = PermissionsManager.shared

        let micInstructions = manager.instructions(for: .microphone)
        #expect(micInstructions.contains("Microphone"))
        #expect(micInstructions.contains("voice"))

        let accessInstructions = manager.instructions(for: .accessibility)
        #expect(accessInstructions.contains("Accessibility"))
        #expect(accessInstructions.contains("hotkey"))
    }

    @Test("Settings URLs are provided for each permission")
    func testSettingsURLs() {
        let manager = PermissionsManager.shared

        let micURL = manager.settingsURL(for: .microphone)
        #expect(micURL != nil)
        #expect(micURL?.absoluteString.contains("Privacy_Microphone") == true)

        let accessURL = manager.settingsURL(for: .accessibility)
        #expect(accessURL != nil)
        #expect(accessURL?.absoluteString.contains("Privacy_Accessibility") == true)
    }

    @Test("Shared instance is singleton")
    func testSingleton() {
        let instance1 = PermissionsManager.shared
        let instance2 = PermissionsManager.shared
        #expect(instance1 === instance2)
    }
}

@Suite("Transcription Error Tests")
struct TranscriptionErrorTests {

    @Test("All error cases have descriptions")
    func testErrorDescriptions() {
        let errors: [TranscriptionError] = [
            .notInitialized,
            .modelLoadFailed("test"),
            .transcriptionFailed("test"),
            .emptyAudio,
            .connectionTimeout
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test("ConnectionTimeout has specific description")
    func testConnectionTimeoutDescription() {
        let error = TranscriptionError.connectionTimeout
        #expect(error.errorDescription?.lowercased().contains("timed out") == true)
    }

    @Test("ModelLoadFailed includes reason")
    func testModelLoadFailedReason() {
        let reason = "Model file not found"
        let error = TranscriptionError.modelLoadFailed(reason)
        #expect(error.errorDescription?.contains(reason) == true)
    }

    @Test("TranscriptionFailed includes reason")
    func testTranscriptionFailedReason() {
        let reason = "Audio too short"
        let error = TranscriptionError.transcriptionFailed(reason)
        #expect(error.errorDescription?.contains(reason) == true)
    }
}

@Suite("Audio Capture Error Tests")
struct AudioCaptureErrorTests {

    @Test("All error cases have descriptions")
    func testErrorDescriptions() {
        let errors: [AudioCaptureError] = [
            .permissionDenied,
            .noInputDevice,
            .engineStartFailed(NSError(domain: "test", code: 1))
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test("PermissionDenied mentions permission")
    func testPermissionDeniedDescription() {
        let error = AudioCaptureError.permissionDenied
        #expect(error.errorDescription?.lowercased().contains("permission") == true)
    }

    @Test("NoInputDevice mentions device")
    func testNoInputDeviceDescription() {
        let error = AudioCaptureError.noInputDevice
        #expect(error.errorDescription?.lowercased().contains("device") == true ||
                error.errorDescription?.lowercased().contains("input") == true)
    }

    @Test("EngineStartFailed includes underlying error")
    func testEngineStartFailedDescription() {
        let underlyingError = NSError(domain: "AudioUnit", code: -10851, userInfo: [NSLocalizedDescriptionKey: "Hardware not available"])
        let error = AudioCaptureError.engineStartFailed(underlyingError)
        #expect(error.errorDescription?.contains("audio engine") == true ||
                error.errorDescription?.contains("Hardware") == true)
    }
}

@Suite("Text Injection Error Tests")
struct TextInjectionErrorTests {

    @Test("All error cases have descriptions")
    func testErrorDescriptions() {
        let errors: [TextInjectionError] = [
            .accessibilityNotGranted,
            .noFocusedElement,
            .injectionFailed,
            .eventCreationFailed
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test("AccessibilityNotGranted mentions accessibility")
    func testAccessibilityNotGrantedDescription() {
        let error = TextInjectionError.accessibilityNotGranted
        #expect(error.errorDescription?.lowercased().contains("accessibility") == true)
    }
}
