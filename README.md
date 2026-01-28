# CmdSpeak

Drop-in replacement for macOS Dictation. Double-tap ⌥, speak, text appears at cursor.

## Installation

### Homebrew (recommended)

```bash
brew tap LxYuan0420/cmdspeak
brew install cmdspeak
```

### Build from source

```bash
git clone https://github.com/LxYuan0420/cmdspeak.git
cd cmdspeak
make install  # Installs to /usr/local/bin
```

## Quick Start

```bash
# Local mode (on-device, private, no API key needed)
cmdspeak run

# OpenAI mode (streaming, requires API key)
export OPENAI_API_KEY=your-key
cmdspeak run-openai
```

**Usage:** `⌥⌥ start → speak → ⌥⌥ stop` (or silence auto-injects)

## Modes

| Mode | Command | Model | Notes |
|------|---------|-------|-------|
| **Local** (default) | `run` or `run-local` | WhisperKit large-v3-turbo | On-device, private, ~1GB download |
| **OpenAI Realtime** | `run-openai` | gpt-4o-transcribe | Streaming, multilingual, requires API key |

The default `run` command auto-selects mode based on your config file.

## Features

- **Double-tap Right Option (⌥⌥)** to start/stop dictation
- **Text injection** at cursor via Accessibility API
- **Menu bar app** for background operation
- **Progress UI** showing model download and loading status
- **Audio feedback** sounds on start/stop
- **Auto-language detection** (or specify language in config)

## Requirements

- macOS 14+ (Sonoma), Apple Silicon recommended
- Permissions: Microphone, Accessibility
- For OpenAI mode: API key
- Disable macOS Dictation: System Settings → Keyboard → Dictation → Shortcut → Off

## Menu Bar App

For background operation, build and run the menu bar app:

```bash
git clone https://github.com/LxYuan0420/cmdspeak.git
cd cmdspeak
swift build -c release
.build/release/CmdSpeakApp
```

## Commands

```bash
cmdspeak run            # Run with mode from config (local or openai-realtime)
cmdspeak run-local      # Force local WhisperKit mode
cmdspeak run-openai     # Force OpenAI streaming mode
cmdspeak status         # Show current config
cmdspeak test-mic       # Test microphone
cmdspeak test-hotkey    # Test ⌥⌥ detection
```

## Configuration

`~/.config/cmdspeak/config.toml`

```toml
[model]
type = "local"                              # "local" or "openai-realtime"
name = "openai_whisper-large-v3_turbo"      # Model name
# language = "en"                           # Optional: force language
# translate_to_english = false              # Optional: translate to English

[hotkey]
trigger = "double-tap-right-option"
interval_ms = 300

[audio]
sample_rate = 16000
silence_threshold_ms = 10000

[feedback]
sound_enabled = true
menu_bar_icon = true
```

### OpenAI mode config

```toml
[model]
type = "openai-realtime"
name = "gpt-4o-transcribe"
api_key = "env:OPENAI_API_KEY"    # Or set OPENAI_API_KEY env var
```

## First Run

On first run with local mode:
1. **Model download** (~954MB for large-v3-turbo)
2. **ANE compilation** (2-4 minutes on first run, cached after)

Progress is shown in CLI and menu bar.

## Architecture

```
User → ⌥⌥ Hotkey → Audio Capture → Transcription Engine → Text Injection
                                          ↓
                           WhisperKit (local) or OpenAI (streaming)
```

## Roadmap

- [x] OpenAI Realtime streaming
- [x] WhisperKit local transcription  
- [x] Menu bar app
- [x] Model download progress UI
- [x] Unified mode selection
- [ ] Homebrew distribution
- [ ] DMG installer

## License

MIT
