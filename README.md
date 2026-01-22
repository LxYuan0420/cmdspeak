# CmdSpeak

A drop-in replacement for macOS Dictation using modern open-source speech models. Same gesture (double-tap Option), same universality, much better transcription.

## Features

- **System-wide** - Works in any text field: browsers, terminals, IDEs, Slack, etc.
- **No UI** - Voice in, text out. No popups, no editors, no AI chat.
- **Local-first** - Uses WhisperKit for on-device inference on Apple Silicon
- **Multi-language** - Auto-detects language or set a specific source language
- **Translation** - Speak any language, get English output
- **Fast** - Target < 500ms from speech end to text injection
- **Private** - Audio never leaves your device

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon Mac (M1/M2/M3/M4)
- Xcode Command Line Tools

## Installation

### From Source

```bash
git clone https://github.com/LxYuan0420/cmdspeak.git
cd cmdspeak
swift build -c release
```

## Usage

### GUI App (Recommended)

```bash
.build/release/CmdSpeakApp
```

The app runs in the menu bar. On first launch:
1. Grant **Microphone** permission when prompted
2. Grant **Accessibility** permission (System Settings > Privacy & Security > Accessibility)
3. The Whisper model will download (~1.5GB for large-v3-turbo)

**Before using, disable macOS Dictation shortcut:**
- System Settings > Keyboard > Dictation > Shortcut > **Off**

Once running:
- Double-tap Right Option key to start dictating
- Speak naturally
- Double-tap again or pause to stop
- Text appears at your cursor

### CLI

```bash
.build/release/cmdspeak status      # Show current state
.build/release/cmdspeak test-mic    # Test microphone (requires Terminal mic permission)
.build/release/cmdspeak reload      # Reload configuration
.build/release/cmdspeak             # Run in CLI mode
```

Note: CLI commands that use the microphone require Terminal.app to have microphone permission in System Settings.

## Configuration

Configuration file: `~/.config/cmdspeak/config.toml`

```toml
[model]
type = "local"
name = "openai_whisper-base"
# language = "zh"           # Optional: source language (auto-detect if not set)
# translate_to_english = true  # Optional: translate to English

[hotkey]
trigger = "double-tap-right-option"
interval_ms = 300

[feedback]
sound_enabled = true
```

### Language Options

```toml
# Auto-detect language (default)
[model]
name = "openai_whisper-base"

# Transcribe Chinese to Chinese
[model]
name = "openai_whisper-base"
language = "zh"

# Translate Chinese to English
[model]
name = "openai_whisper-base"
language = "zh"
translate_to_english = true

# Auto-detect any language and translate to English
[model]
name = "openai_whisper-base"
translate_to_english = true
```

Supported languages: en, zh, ja, ko, es, fr, de, it, pt, ru, ar, hi, and 90+ more.

### Available Models

- `openai_whisper-base` (default) - Small and fast, ~150MB
- `openai_whisper-small` - Better quality, ~500MB
- `openai_whisper-large-v3-turbo` - Best quality, ~1.5GB

See all models: https://huggingface.co/argmaxinc/whisperkit-coreml

## How It Works

```
Double-tap Option -> AudioCapture -> VAD -> WhisperKit -> TextInjection -> Cursor
```

1. **Hotkey Detection** - Detects double-tap of Right Option key via CGEventTap
2. **Audio Capture** - Records audio from microphone via AVCaptureSession
3. **VAD** - Voice Activity Detection determines when you stop speaking
4. **Transcription** - WhisperKit transcribes audio locally using CoreML/ANE
5. **Text Injection** - Injects text at cursor via macOS Accessibility APIs

## Permissions Required

| Permission | Why |
|------------|-----|
| Microphone | To capture your voice |
| Accessibility | To inject text and detect hotkeys |

## Privacy

- All audio processing happens on-device by default
- No telemetry or analytics
- API models (OpenAI, etc.) are opt-in and require explicit configuration

## Development

```bash
swift build             # Debug build
swift build -c release  # Release build
swift test              # Run tests
swiftlint               # Lint code
swiftformat .           # Format code
```

### Test Commands

```bash
.build/debug/cmdspeak test-mic          # Test microphone capture
.build/debug/cmdspeak test-hotkey       # Test hotkey detection
.build/debug/cmdspeak test-transcribe   # Test model + transcription
.build/debug/cmdspeak test-integration  # Test full pipeline
```

## License

MIT
