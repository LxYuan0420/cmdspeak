# CmdSpeak Engineering Guide

## Project Overview
CmdSpeak is a drop-in replacement for macOS Dictation using modern open-source speech models (MLX-based for Apple Silicon).

## Commands
```bash
# Build
swift build

# Build release
swift build -c release

# Run tests
swift test

# Lint
swiftlint

# Format
swiftformat .

# Run app
swift run cmdspeak
```

## Architecture Principles

### 1. Performance First
- **Latency beats features** - "feels instant" is the goal
- Target < 500ms from speech end to text injection
- Use MLX for Apple Silicon native inference
- Minimize memory footprint (< 500MB idle)

### 2. System-Native Design
- Pure Swift + SwiftUI for macOS integration
- Use native macOS APIs: Accessibility, AudioToolbox, CoreAudio
- No Electron, no web views, no bridges
- Menu bar app with minimal UI

### 3. Modular Engine Architecture
```
AudioInput → VAD → TranscriptionEngine → TextPostProcessor → TextInjection
```
Each component is pluggable with clear interfaces.

### 4. Code Style
- Swift 5.9+ with strict concurrency
- Use `async/await` for all async operations
- Prefer value types (structs) over reference types
- All public APIs must be documented
- No force unwraps in production code
- Error handling via `Result` or throwing functions

### 5. File Organization
```
Sources/
  CmdSpeak/
    App/           # SwiftUI app entry, menu bar
    Audio/         # Mic capture, VAD
    Engine/        # Transcription engines (MLX, API)
    Injection/     # Text injection via Accessibility
    Config/        # TOML config parsing
    CLI/           # Command-line interface
Resources/
  Models/          # Bundled model weights (optional)
Tests/
  CmdSpeakTests/
```

### 6. Configuration
- Single source: `~/.config/cmdspeak/config.toml`
- Environment variables for secrets: `env:OPENAI_API_KEY`
- Sensible defaults for zero-config experience

### 7. Testing Strategy
- Unit tests for all engine components
- Integration tests for audio → text pipeline
- UI tests for menu bar interactions
- Mock audio input for deterministic tests

### 8. Security
- No telemetry
- Audio never leaves device unless API model explicitly configured
- Keychain for any stored credentials
- Accessibility permissions are scoped and explained

### 9. PR Requirements
- Clear title and description
- Link to GitHub issue
- All tests passing
- No compiler warnings
- Reviewed diff < 400 lines preferred

### 10. Dependencies
Minimize external dependencies:
- **MLX-Swift** - Apple Silicon ML inference
- **TOMLKit** - Config parsing
- **swift-argument-parser** - CLI

## Key Technical Decisions
- **Inference**: MLX (Apple Silicon native, fast, local)
- **Model**: whisper-large-v3-turbo via MLX (best quality/speed tradeoff)
- **Language**: Swift (native macOS, performance, Accessibility APIs)
- **Distribution**: Homebrew tap + DMG
