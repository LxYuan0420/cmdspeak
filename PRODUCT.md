# CmdSpeak Product Document

## Overview

CmdSpeak is a macOS voice-to-text application that replaces macOS Dictation with modern speech models. Double-tap Right Option (⌥⌥) to start dictation, speak, and text is injected at the cursor.

## Current Status

**Version:** 0.1.0  
**Primary Mode:** OpenAI Realtime API (recommended)  
**Secondary Mode:** WhisperKit Local (on-device)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      User Interface                          │
├─────────────────┬───────────────────────────────────────────┤
│   CLI (cmdspeak)│         Menu Bar App (CmdSpeakApp)        │
└────────┬────────┴───────────────────┬───────────────────────┘
         │                            │
         ▼                            ▼
┌─────────────────────────────────────────────────────────────┐
│               OpenAIRealtimeController                       │
│  - State machine (idle→connecting→listening→finalizing)     │
│  - Session management (UUID per session)                     │
│  - Reconnection with exponential backoff                     │
│  - Silence timeout detection                                 │
└────────────────────────┬────────────────────────────────────┘
                         │
    ┌────────────────────┼────────────────────┐
    ▼                    ▼                    ▼
┌──────────┐    ┌──────────────────┐    ┌──────────────┐
│ Hotkey   │    │ OpenAIRealtime   │    │ AudioCapture │
│ Manager  │    │ Engine           │    │ Manager      │
│          │    │                  │    │              │
│ ⌥⌥ detect│    │ WebSocket        │    │ Mic capture  │
│          │    │ PCM16 encoding   │    │ Resampling   │
└──────────┘    │ Event handling   │    └──────────────┘
                └────────┬─────────┘
                         │
                         ▼
                ┌──────────────────┐
                │  TextInjector    │
                │  Accessibility   │
                │  API injection   │
                └──────────────────┘
```

---

## Features Completed ✅

### Core Functionality
- [x] Double-tap Right Option hotkey detection
- [x] OpenAI Realtime API WebSocket streaming
- [x] Real-time transcription with delta streaming
- [x] Multi-segment transcript accumulation (fixed: was losing text)
- [x] Text injection at cursor via Accessibility API
- [x] Fallback paste injection when Accessibility fails
- [x] Audio feedback sounds (start/stop)

### Production Hardening
- [x] Session ID to prevent race conditions on rapid toggling
- [x] Reconnection with exponential backoff (3 attempts)
- [x] Session-ready gating (waits for WebSocket handshake)
- [x] Configuration validation at startup
- [x] Intentional vs unexpected disconnect handling
- [x] Receive task tracking and cleanup
- [x] State transition logging

### User Interface
- [x] CLI mode (`cmdspeak run-openai`)
- [x] Menu bar app with status indicator
- [x] Real-time transcription preview in terminal

### Testing
- [x] 62 unit tests passing
- [x] Engine message handling tests
- [x] Multi-segment accumulation regression tests
- [x] PCM16 conversion tests
- [x] Configuration validation tests

---

## Known Issues 🐛

### High Priority
1. ~~**Unbounded Task creation for audio sends**~~ ✅ FIXED
   - Now uses bounded AsyncStream with 50-buffer limit
   - Single sender task processes queue sequentially

2. **Polling-based session/transcript waiting**
   - `waitForSessionReady()` and `awaitFinalTranscript()` poll every 50ms
   - Should use `CheckedContinuation` for proper async signaling

3. **Naive audio resampling (nearest-neighbor)**
   - Current: `channelData[srcIndex]` with integer truncation
   - Causes aliasing and reduces transcription accuracy
   - Fix: Use `AVAudioConverter` for proper resampling

### Medium Priority
4. **Silence detection based on transcription deltas, not audio**
   - Can timeout mid-speech if model/network is slow
   - Should use server VAD events (`speech_started`/`speech_stopped`)

5. **Short final transcript timeout (1s)**
   - Can miss final words under network variance
   - Should be 3-5s or use proper completion signaling

6. **No explicit reconnecting state in UI**
   - User sees "connecting" but doesn't know it's a retry

### Low Priority
7. **Manual PCM buffer unpacking loops**
   - Inefficient; should use AVAudioEngine tap
8. **Base64 encoding overhead**
   - Could batch larger frames (50-100ms)
9. **No microphone device selection**

---

## Roadmap 🗺️

### Phase 1: Core Stability (Current)
- [x] Multi-segment transcript fix
- [x] Session ID race condition fix
- [x] Reconnection with backoff
- [x] Menu bar app for background operation
- [x] **Bounded audio send pipeline** (AsyncStream with 50-buffer limit)
- [x] **Increased final transcript timeout** (1s → 3s)
- [ ] **AVAudioConverter resampling** ⬅️ NEXT
- [ ] **CheckedContinuation for async signals**

### Phase 2: Reliability
- [ ] Server VAD-based endpointing
- [ ] Error code classification (fatal vs transient)
- [ ] Connection timeout enforcement
- [ ] Proper disconnect callback semantics
- [ ] Telemetry hooks (latency, drops)

### Phase 3: User Experience
- [ ] Reconnecting state with UI feedback
- [ ] Hotkey during connecting = cancel
- [ ] Hotkey during finalizing = force inject
- [ ] Microphone device selection
- [ ] Input level indicator
- [ ] VAD threshold configuration

### Phase 4: Distribution
- [ ] Code signing for Gatekeeper
- [ ] Homebrew formula
- [ ] DMG installer
- [ ] Auto-update mechanism

---

## Technical Debt

| Issue | Impact | Effort | Priority | Status |
|-------|--------|--------|----------|--------|
| ~~Unbounded audio Task spawning~~ | High (memory/latency) | M (2-3h) | P0 | ✅ Done |
| Nearest-neighbor resampling | Medium (accuracy) | M (2-3h) | P0 | Next |
| Polling async waits | Medium (races) | M (2-3h) | P1 | |
| Manual CMSampleBuffer loops | Low (perf) | L (1-2d) | P2 | |
| Stringly-typed JSON events | Low (maintainability) | M (2-3h) | P2 | |

---

## Configuration

File: `~/.config/cmdspeak/config.toml`

```toml
[model]
type = "openai-realtime"
name = "gpt-4o-transcribe"
api_key = "env:OPENAI_API_KEY"
# language = "en"  # Optional: force language

[hotkey]
trigger = "double-tap-right-option"
interval_ms = 300

[audio]
sample_rate = 16000
silence_threshold_ms = 10000  # 10s silence triggers inject

[feedback]
sound_enabled = true
menu_bar_icon = true
```

---

## Test Coverage

| Suite | Tests | Status |
|-------|-------|--------|
| OpenAI Realtime Engine | 17 | ✅ |
| PCM16 Conversion | 9 | ✅ |
| Message Handling | 13 | ✅ |
| Controller State | 5 | ✅ |
| Config | 8 | ✅ |
| Hotkey Logic | 4 | ✅ |
| VAD | 4 | ✅ |
| **Total** | **62** | ✅ |

### Missing Test Coverage
- [ ] Controller state machine transitions (mock engine)
- [ ] Reconnection flow simulation
- [ ] Audio pipeline end-to-end (offline)
- [ ] WebSocket integration test (with real API, optional)

---

## Commands

```bash
# Build
swift build -c release

# Run CLI
export OPENAI_API_KEY=your-key
.build/release/cmdspeak run-openai

# Run Menu Bar App (recommended for background use)
export OPENAI_API_KEY=your-key
.build/release/CmdSpeakApp

# Test
swift test

# Test specific component
swift run cmdspeak test-mic
swift run cmdspeak test-hotkey
swift run cmdspeak test-openai
```

---

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| WhisperKit | 0.15.0+ | Local transcription engine |
| TOMLKit | 0.6.0+ | Configuration parsing |
| ArgumentParser | 1.3.0+ | CLI interface |

---

## Changelog

### 2026-01-23
- Fixed: Multi-segment transcripts now accumulate properly (was only keeping last segment)
- Fixed: Unbounded Task spawning per audio buffer → bounded AsyncStream pipeline
- Added: Session ID to prevent race conditions on rapid hotkey toggling
- Added: Reconnection with exponential backoff (3 attempts)
- Added: Session-ready gating before sending audio
- Added: Menu bar app for true background operation
- Added: `finalizing` state for visibility
- Added: Configuration validation at startup
- Added: 8 new regression tests for transcript accumulation
- Improved: Final transcript timeout increased from 1s to 3s
- Improved: Logging with state transitions
- Improved: Disconnect handling (intentional vs unexpected)
