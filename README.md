# CmdSpeak

[![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange.svg)](https://swift.org)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue.svg)](https://developer.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Drop-in replacement for macOS Dictation. Double-tap ⌥⌥, speak, text appears at cursor.

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

**Usage:** Double-tap Right Option (⌥⌥) to start → speak → ⌥⌥ to stop (or wait for silence auto-inject)

## Modes

| Mode | Command | Model | Notes |
|------|---------|-------|-------|
| **Local** (default) | `run` or `run-local` | WhisperKit large-v3-turbo | On-device, private, ~1GB download |
| **OpenAI Realtime** | `run-openai` | gpt-4o-transcribe | Streaming, multilingual, requires API key |

The default `run` command auto-selects mode based on your config file.

## Features

- **Double-tap Right Option (⌥⌥)** to start/stop dictation
- **Text injection** at cursor via Accessibility API
- **Streaming transcription** — see words appear in real-time
- **Multi-language support** — auto-detects 99+ languages per utterance
- **Voice Activity Detection** — auto-stops after silence
- **Menu bar app** for background operation with visual feedback
- **Progress UI** showing model download and loading status
- **Audio feedback** sounds on start/stop

## Requirements

- macOS 14+ (Sonoma), Apple Silicon recommended
- Permissions: Microphone, Accessibility
- For OpenAI mode: API key
- Disable macOS Dictation: System Settings → Keyboard → Dictation → Shortcut → Off

## Menu Bar App

For background operation, build and run the menu bar app:

```bash
swift build -c release
.build/release/CmdSpeakApp
```

The menu bar app shows:
- **Status indicator** — color-coded (green=ready, blue=listening, purple=processing)
- **Live transcription** — see text as you speak
- **Download progress** — model download and ANE compilation status

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
# language = "en"                           # Optional: force language (omit for auto-detect)
# translate_to_english = false              # Optional: translate all speech to English

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

## Troubleshooting

### Hotkey not working
- Ensure Accessibility permission is granted: System Settings → Privacy & Security → Accessibility → Enable CmdSpeak
- Disable macOS Dictation shortcut: System Settings → Keyboard → Dictation → Shortcut → Off

### No audio captured
- Grant Microphone permission: System Settings → Privacy & Security → Microphone → Enable CmdSpeak
- Check audio input device: System Settings → Sound → Input

### Model loading slow on first run
- ANE compilation takes 2-4 minutes on first run (cached after)
- Progress is shown in CLI and menu bar

## Roadmap

- [x] OpenAI Realtime streaming
- [x] WhisperKit local transcription  
- [x] Menu bar app with visual feedback
- [x] Model download progress UI
- [x] Unified mode selection
- [x] Streaming transcription for local mode
- [x] Homebrew distribution
- [x] Voice Activity Detection (VAD)
- [ ] System permissions onboarding flow
- [ ] DMG installer
- [ ] Code signing for Gatekeeper

## Contributing

Contributions welcome! Please open an issue or pull request.

## License

MIT
