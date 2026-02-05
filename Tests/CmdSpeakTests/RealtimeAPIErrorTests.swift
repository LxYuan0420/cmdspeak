import Foundation
import Testing
@testable import CmdSpeakCore

@Suite("Realtime API Error Tests")
struct RealtimeAPIErrorTests {

    @Test("Fatal error codes are classified correctly")
    func testFatalErrorCodes() {
        let fatalCodes = [
            "invalid_api_key",
            "invalid_request_error",
            "model_not_found",
            "insufficient_quota"
        ]

        for code in fatalCodes {
            let error = RealtimeAPIError(code: code, message: "Test")
            #expect(error.isFatal, "Expected \(code) to be fatal")
        }
    }

    @Test("Transient error codes are not fatal")
    func testTransientErrorCodes() {
        let transientCodes = [
            "rate_limit_exceeded",
            "server_error",
            "timeout"
        ]

        for code in transientCodes {
            let error = RealtimeAPIError(code: code, message: "Test")
            #expect(!error.isFatal, "Expected \(code) to be transient")
        }
    }

    @Test("Fatal messages without code are classified correctly")
    func testFatalMessages() {
        let fatalMessages = [
            "Invalid API key provided",
            "Authentication failed",
            "Unauthorized access",
            "Model not found",
            "Billing issue detected",
            "Quota exceeded"
        ]

        for message in fatalMessages {
            let error = RealtimeAPIError(code: nil, message: message)
            #expect(error.isFatal, "Expected message '\(message)' to be fatal")
        }
    }

    @Test("Error description includes code when present")
    func testErrorDescriptionWithCode() {
        let error = RealtimeAPIError(code: "rate_limit", message: "Too many requests")
        #expect(error.errorDescription?.contains("[rate_limit]") == true)
        #expect(error.errorDescription?.contains("Too many requests") == true)
    }

    @Test("Error description without code shows message only")
    func testErrorDescriptionWithoutCode() {
        let error = RealtimeAPIError(code: nil, message: "Something went wrong")
        #expect(error.errorDescription == "Something went wrong")
    }

    @Test("Recovery hints are provided for known errors")
    func testRecoveryHints() {
        let apiKeyError = RealtimeAPIError(code: "invalid_api_key", message: "Bad key")
        #expect(apiKeyError.recoveryHint?.contains("OPENAI_API_KEY") == true)

        let quotaError = RealtimeAPIError(code: "insufficient_quota", message: "No quota")
        #expect(quotaError.recoveryHint?.contains("billing") == true)

        let modelError = RealtimeAPIError(code: "model_not_found", message: "No model")
        #expect(modelError.recoveryHint?.contains("config.toml") == true)

        let rateLimitError = RealtimeAPIError(code: "rate_limit", message: "Slow down")
        #expect(rateLimitError.recoveryHint?.contains("Wait") == true)
    }

    @Test("Unknown errors have no recovery hint")
    func testNoRecoveryHintForUnknownErrors() {
        let error = RealtimeAPIError(code: "unknown_error", message: "Something happened")
        #expect(error.recoveryHint == nil)
    }

    @Test("Error conforms to Error protocol")
    func testErrorProtocolConformance() {
        let error: Error = RealtimeAPIError(code: "test", message: "Test message")
        #expect(error.localizedDescription.contains("Test message"))
    }
}
