# CmdSpeak

Drop-in replacement for macOS Dictation. Double-tap ⌥, speak, text appears at cursor.

> **Current Focus:** OpenAI Realtime API  
> **Next:** MLX-based on-device models

## Quick Start

```bash
git clone https://github.com/LxYuan0420/cmdspeak.git
cd cmdspeak
swift build -c release

export OPENAI_API_KEY=your-key
.build/release/CmdSpeakApp          # Menu bar app (recommended)
# or
.build/release/cmdspeak run-openai  # CLI mode
```

**Usage:** `⌥⌥ start → speak → ⌥⌥ stop` (or 10s silence auto-injects)

## Requirements

- macOS 14+ (Sonoma), Apple Silicon
- OpenAI API key
- Permissions: Microphone, Accessibility
- Disable macOS Dictation: System Settings → Keyboard → Dictation → Shortcut → Off

## Modes

| Mode | Command | Notes |
|------|---------|-------|
| **OpenAI Realtime** ✨ | `run-openai` | Streaming, multilingual, recommended |
| WhisperKit Local | `run` | On-device, private, slower |

## Commands

```bash
cmdspeak run-openai     # OpenAI streaming mode
cmdspeak run            # Local WhisperKit mode
cmdspeak test-mic       # Test microphone
cmdspeak test-hotkey    # Test ⌥⌥ detection
cmdspeak status         # Show config
```

## Configuration

`~/.config/cmdspeak/config.toml`

```toml
[model]
type = "openai-realtime"
name = "gpt-4o-transcribe"

[hotkey]
interval_ms = 300

[audio]
silence_threshold_ms = 10000

[feedback]
sound_enabled = true
```

## Roadmap

- [x] OpenAI Realtime streaming
- [x] WhisperKit local transcription
- [x] Menu bar app
- [ ] MLX-based local models
- [ ] Homebrew distribution

## License

MIT
