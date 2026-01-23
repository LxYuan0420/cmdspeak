# CmdSpeak

A drop-in replacement for macOS Dictation using modern speech models. Same gesture (double-tap Option), works everywhere, much better transcription.

> **Current Focus:** OpenAI Realtime API for production-quality streaming transcription  
> **Next:** MLX-based open-source models for fully on-device, private transcription

## Features

- **System-wide** - Works in any text field: browsers, terminals, IDEs, Slack, etc.
- **No UI** - Voice in, text out. No popups, no editors, no AI chat.
- **Two modes**:
  - **OpenAI Realtime** - Streaming transcription via API (recommended) ✨
  - **WhisperKit Local** - On-device inference on Apple Silicon
- **Multi-language** - Auto-detects language, supports mixed language content
- **Fast** - Real-time streaming transcription with OpenAI mode
- **Private** - Local mode keeps audio on-device

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon Mac (M1/M2/M3/M4)
- Xcode Command Line Tools
- OpenAI API key (for OpenAI mode)

## Installation

```bash
git clone https://github.com/LxYuan0420/cmdspeak.git
cd cmdspeak
swift build -c release
```

## Quick Start (OpenAI Mode) ✨

```bash
export OPENAI_API_KEY=your-key
swift run cmdspeak run-openai
```

**Workflow:**
```
⌥⌥ start → speak → ⌥⌥ stop (or 10s silence)
```

1. Double-tap Right Option → start listening
2. Speak (see transcription in real-time)
3. Double-tap again OR wait 10s silence → text injected at cursor

## Permissions

Before first use:
1. Grant **Microphone** permission when prompted
2. Grant **Accessibility** permission: System Settings > Privacy & Security > Accessibility
3. **Disable macOS Dictation shortcut**: System Settings > Keyboard > Dictation > Shortcut > **Off**

## Usage

### OpenAI Realtime Mode (Recommended)

```bash
export OPENAI_API_KEY=your-key
swift run cmdspeak run-openai
```

Features:
- Streaming transcription (see text as you speak)
- Server-side VAD (auto-detects speech)
- Multilingual support (English, Chinese, mixed content)
- 10 second silence auto-inject

### Local WhisperKit Mode

```bash
swift run cmdspeak              # Default local mode
swift run cmdspeak test-mic     # Test microphone
swift run cmdspeak status       # Show configuration
```

### Test Commands

```bash
swift run cmdspeak test-openai      # Test OpenAI API
swift run cmdspeak test-mic         # Test microphone
swift run cmdspeak test-hotkey      # Test hotkey detection
swift run cmdspeak test-transcribe  # Test local transcription
```

## Configuration

Configuration file: `~/.config/cmdspeak/config.toml`

```toml
# OpenAI Realtime Mode
[model]
type = "openai-realtime"
name = "gpt-4o-transcribe"
api_key = "env:OPENAI_API_KEY"

# Local WhisperKit Mode
[model]
type = "local"
name = "openai_whisper-base"
# language = "zh"              # Optional: source language
# translate_to_english = true  # Optional: translate to English

[hotkey]
trigger = "double-tap-right-option"
interval_ms = 300

[audio]
silence_threshold_ms = 10000  # 10 seconds

[feedback]
sound_enabled = true
```

### Local Models (WhisperKit)

- `openai_whisper-base` - Small and fast, ~150MB
- `openai_whisper-small` - Better quality, ~500MB
- `openai_whisper-large-v3-turbo` - Best quality, ~1.5GB

## How It Works

### OpenAI Realtime Mode
```
⌥⌥ → WebSocket → Stream Audio → Realtime Transcription → Text Injection
```

### Local Mode
```
⌥⌥ → AudioCapture → WhisperKit → Text Injection
```

## Roadmap

- [x] OpenAI Realtime streaming transcription
- [x] Local WhisperKit transcription
- [x] Multilingual support
- [x] Menu bar app with visual feedback
- [ ] MLX-based local models (Whisper, distil-whisper)
- [ ] Homebrew distribution
- [ ] WhisperKit streaming mode

## License

MIT
