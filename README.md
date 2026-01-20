# CmdSpeak

A drop-in replacement for macOS Dictation using modern open-source speech models. Same gesture (double-tap ⌘), same universality, much better transcription.

## Features

- **System-wide** - Works in any text field: browsers, terminals, IDEs, Slack, etc.
- **No UI** - Voice in → text out. No popups, no editors, no "AI chat"
- **Local-first** - Uses WhisperKit for on-device inference on Apple Silicon
- **Fast** - Target < 500ms from speech end to text injection
- **Private** - Audio never leaves your device unless you configure an API model

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon Mac (M1/M2/M3)

## Installation

### Homebrew (coming soon)

```bash
brew install cmdspeak
```

### From Source

```bash
git clone https://github.com/LxYuan0420/cmdspeak.git
cd cmdspeak
swift build -c release
```

## Usage

1. Launch CmdSpeak (it runs in the menu bar)
2. Grant microphone and accessibility permissions when prompted
3. Double-tap Right Command (⌘) to start dictating
4. Speak naturally
5. Text appears at your cursor

### CLI Commands

```bash
cmdspeak status      # Show current state
cmdspeak test-mic    # Test microphone input
cmdspeak reload      # Reload configuration
```

## Configuration

Configuration file: `~/.config/cmdspeak/config.toml`

```toml
[model]
type = "local"
name = "openai/whisper-large-v3-turbo"

[hotkey]
trigger = "double-tap-right-cmd"
interval_ms = 300

[audio]
sample_rate = 16000
silence_threshold_ms = 500

[feedback]
sound_enabled = true
menu_bar_icon = true
```

## How It Works

```
Double-tap ⌘ → AudioCapture → VAD → WhisperKit → TextInjection → Cursor
```

1. **Hotkey Detection** - Detects double-tap of Right Command key
2. **Audio Capture** - Records 16kHz mono audio from microphone
3. **VAD** - Voice Activity Detection determines when you stop speaking
4. **Transcription** - WhisperKit transcribes audio locally on Apple Silicon
5. **Text Injection** - Injects text at cursor via macOS Accessibility APIs

## Privacy

- All audio processing happens on-device by default
- No telemetry or analytics
- API models (OpenAI, etc.) are opt-in and require explicit configuration

## License

MIT
