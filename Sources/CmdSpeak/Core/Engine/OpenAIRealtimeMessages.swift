import Foundation

// MARK: - Outgoing Messages (Client → Server)

/// Base protocol for all outgoing messages
protocol OpenAIOutgoingMessage: Encodable {
    var type: String { get }
}

/// Append audio to the input buffer
struct InputAudioBufferAppend: OpenAIOutgoingMessage {
    let type = "input_audio_buffer.append"
    let audio: String
}

/// Commit the audio buffer for processing
struct InputAudioBufferCommit: OpenAIOutgoingMessage {
    let type = "input_audio_buffer.commit"
}

/// Update transcription session configuration
struct TranscriptionSessionUpdate: OpenAIOutgoingMessage {
    let type = "transcription_session.update"
    let session: SessionConfig

    struct SessionConfig: Encodable {
        let inputAudioFormat: String
        let inputAudioTranscription: TranscriptionConfig
        let turnDetection: TurnDetection

        enum CodingKeys: String, CodingKey {
            case inputAudioFormat = "input_audio_format"
            case inputAudioTranscription = "input_audio_transcription"
            case turnDetection = "turn_detection"
        }
    }

    struct TranscriptionConfig: Encodable {
        let model: String
        let prompt: String
        var language: String?
    }

    struct TurnDetection: Encodable {
        let type: String
        let threshold: Double
        let prefixPaddingMs: Int
        let silenceDurationMs: Int

        enum CodingKeys: String, CodingKey {
            case type
            case threshold
            case prefixPaddingMs = "prefix_padding_ms"
            case silenceDurationMs = "silence_duration_ms"
        }
    }

    init(model: String, language: String?) {
        var transcriptionConfig = TranscriptionConfig(
            model: model,
            prompt: "Transcribe in any language including mixed language content"
        )
        transcriptionConfig.language = language

        self.session = SessionConfig(
            inputAudioFormat: "pcm16",
            inputAudioTranscription: transcriptionConfig,
            turnDetection: TurnDetection(
                type: "server_vad",
                threshold: 0.5,
                prefixPaddingMs: 100,
                silenceDurationMs: 300
            )
        )
    }
}

// MARK: - Incoming Messages (Server → Client)

/// Wrapper for decoding incoming messages by type
struct OpenAIIncomingMessage: Decodable {
    let type: String

    private enum CodingKeys: String, CodingKey {
        case type
    }
}

/// Transcription session created
struct TranscriptionSessionCreated: Decodable {
    let type: String
}

/// Transcription session updated
struct TranscriptionSessionUpdated: Decodable {
    let type: String
}

/// Partial transcription delta
struct TranscriptionDelta: Decodable {
    let type: String
    let delta: String
}

/// Transcription completed for a segment
struct TranscriptionCompleted: Decodable {
    let type: String
    let transcript: String
}

/// Speech started event
struct SpeechStarted: Decodable {
    let type: String
}

/// Speech stopped event
struct SpeechStopped: Decodable {
    let type: String
}

/// Audio buffer committed
struct AudioBufferCommitted: Decodable {
    let type: String
}

/// Error event
struct OpenAIError: Decodable {
    let type: String
    let error: ErrorDetails

    struct ErrorDetails: Decodable {
        let message: String
        let code: String?
    }
}

// MARK: - Event Types

enum OpenAIEventType: String {
    case sessionCreated = "transcription_session.created"
    case sessionUpdated = "transcription_session.updated"
    case transcriptionDelta = "conversation.item.input_audio_transcription.delta"
    case transcriptionCompleted = "conversation.item.input_audio_transcription.completed"
    case speechStarted = "input_audio_buffer.speech_started"
    case speechStopped = "input_audio_buffer.speech_stopped"
    case audioCommitted = "input_audio_buffer.committed"
    case error = "error"
}
