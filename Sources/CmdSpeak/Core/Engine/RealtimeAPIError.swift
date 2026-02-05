import Foundation

/// Typed error from OpenAI Realtime API.
public struct RealtimeAPIError: Error, Sendable, LocalizedError {
    public let code: String?
    public let message: String
    
    public init(code: String?, message: String) {
        self.code = code
        self.message = message
    }
    
    /// Whether this error is fatal (should not retry).
    public var isFatal: Bool {
        guard let code = code?.lowercased() else {
            return isFatalMessage
        }
        
        let fatalCodes = [
            "invalid_api_key",
            "invalid_request_error", 
            "model_not_found",
            "insufficient_quota"
        ]
        
        return fatalCodes.contains(where: { code.contains($0) }) || isFatalMessage
    }
    
    private var isFatalMessage: Bool {
        let lower = message.lowercased()
        return lower.contains("invalid api key") ||
               lower.contains("authentication") ||
               lower.contains("unauthorized") ||
               lower.contains("model not found") ||
               lower.contains("billing") ||
               lower.contains("quota")
    }
    
    /// User-friendly description.
    public var errorDescription: String? {
        if let code = code {
            return "[\(code)] \(message)"
        }
        return message
    }
    
    /// Recovery hint for the user.
    public var recoveryHint: String? {
        guard let code = code?.lowercased() else { return nil }
        
        if code.contains("invalid_api_key") || code.contains("authentication") {
            return "Check OPENAI_API_KEY environment variable"
        }
        if code.contains("insufficient_quota") || code.contains("billing") {
            return "Check your OpenAI account billing status"
        }
        if code.contains("model_not_found") {
            return "Update model name in ~/.config/cmdspeak/config.toml"
        }
        if code.contains("rate_limit") {
            return "Wait a moment and try again"
        }
        return nil
    }
}
