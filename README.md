# CmdSpeak

[![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange.svg)](https://swift.org)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue.svg)](https://developer.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Drop-in replacement for macOS Dictation. Double-tap Right Option, speak, text appears at cursor.

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
export OPENAI_API_KEY=your-key
cmdspeak
```

**Usage:** Double-tap Right Option to start, speak, double-tap again to stop (or wait for silence auto-inject)

## Features

- **Double-tap Right Option** to start/stop dictation
- **Streaming transcription** with OpenAI gpt-4o-transcribe
- **Text injection** at cursor via Accessibility API
- **Multi-language support** — auto-detects 99+ languages
- **Voice Activity Detection** — auto-stops after silence
- **Menu bar app** for background operation with visual feedback
- **Audio feedback** sounds on start/stop

## Requirements

- macOS 14+ (Sonoma)
- OpenAI API key
- Permissions: Microphone, Accessibility
- Disable macOS Dictation: System Settings → Keyboard → Dictation → Shortcut → Off

## Menu Bar App

For background operation:

```bash
swift build -c release
.build/release/CmdSpeakApp
```

The menu bar shows:
- **Status indicator** — color-coded (green=ready, blue=listening, purple=processing)
- **Live transcription** — see text as you speak

## Commands

```bash
cmdspeak             # Run dictation
cmdspeak setup       # Setup permissions (guided onboarding)
cmdspeak status      # Show current config and permissions
cmdspeak test-mic    # Test microphone
cmdspeak test-hotkey # Test double-tap detection
cmdspeak test-openai # Test OpenAI API connection
```

## Configuration

`~/.config/cmdspeak/config.toml`

```toml
[model]
name = "gpt-4o-transcribe"
# api_key = "env:OPENAI_API_KEY"  # Or set OPENAI_API_KEY env var
# language = "en"                  # Optional: force language (omit for auto-detect)

[hotkey]
trigger = "double-tap-right-option"
interval_ms = 300

[audio]
sample_rate = 24000
silence_threshold_ms = 10000

[feedback]
sound_enabled = true
menu_bar_icon = true
```

## Troubleshooting

### First-time setup
Run `cmdspeak setup` for guided permission configuration.

### Hotkey not working
- Run `cmdspeak setup` to check and fix permissions
- Ensure Accessibility permission is granted: System Settings → Privacy & Security → Accessibility
- Disable macOS Dictation shortcut: System Settings → Keyboard → Dictation → Shortcut → Off

### No audio captured
- Run `cmdspeak setup` to check microphone permission
- Grant Microphone permission: System Settings → Privacy & Security → Microphone

### API key not found
- Set `OPENAI_API_KEY` environment variable, or
- Add `api_key = "your-key"` to config.toml

## Contributing

Contributions welcome! Please open an issue or pull request.

## License

MIT
