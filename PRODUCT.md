# CmdSpeak Product Document

## Overview

CmdSpeak is a macOS voice-to-text application that replaces macOS Dictation with modern speech models. Double-tap Right Option (⌥⌥) to start dictation, speak, and text is injected at the cursor.

## Current Status

**Version:** 0.3.0  
**Mode:** OpenAI Realtime API only (streaming, requires internet)  
**Distribution:** Homebrew tap available (`brew tap LxYuan0420/cmdspeak`)

### Open Issues
- [#27 System permissions onboarding flow](https://github.com/LxYuan0420/cmdspeak/issues/27)

---

## TODO: Fix Audio Capture Crash (Priority P0)

**Date:** 2026-01-31

**Symptom:** App crashes or fails with audio errors on startup or restart:
- `Input HW format and tap format not matching` (NSException crash)
- `com.apple.coreaudio.avfaudio error -10868` (engine start failed)

**Root Cause:** AVAudioEngine input node format mismatch. The format passed to `installTap` doesn't match what the hardware expects.

**What we tried:**
1. ❌ Pass `nil` for format → crashes on restart
2. ❌ Use `inputFormat(forBus:)` → format mismatch
3. ❌ Use `outputFormat(forBus:)` → format mismatch
4. ❌ Call `engine.reset()` before setup → still crashes
5. ❌ Access `inputFormat` first to initialize node → error -10868

**Next steps to try:**
1. [ ] Use AVCaptureSession instead of AVAudioEngine (more stable API)
2. [ ] Add retry logic with delay between attempts
3. [ ] Check if audio device changed and handle gracefully
4. [ ] Test on clean macOS restart
5. [ ] Research error -10868 (kAudioUnitErr_FormatNotSupported?)
6. [ ] Try creating format manually with known good values (48kHz, 1ch, Float32)

**Files to modify:**
- `Sources/CmdSpeak/Core/Audio/AudioCaptureManager.swift`

**References:**
- https://developer.apple.com/documentation/avfaudio/avaudioengine
- https://stackoverflow.com/questions/tagged/avaudioengine+format

---

## Deprecation: Remove Local WhisperKit Mode

**Decision Date:** 2026-01-31

**Rationale:**
- OpenAI Realtime API provides superior transcription quality
- Local mode has UX issues: timestamp tokens leaking (`<|17.00|>`), emoji in output
- Local mode requires ~1GB model download + 2-4 min ANE compilation on first run
- Maintaining two transcription backends adds complexity
- Simplifying to one mode improves code quality and user experience

**Files to Remove:**
- `Sources/CmdSpeak/Core/Engine/WhisperKitEngine.swift`
- `Sources/CmdSpeak/Core/CmdSpeakController.swift` (local mode controller)
- `Sources/CmdSpeak/Core/Audio/VoiceActivityDetector.swift` (only used by local mode)

**Files to Modify:**
- `Package.swift` - remove WhisperKit dependency
- `Sources/CmdSpeak/CLI/CmdSpeakCLI.swift` - remove `run-local`, `run` commands, keep only `run-openai` (rename to `run`)
- `Sources/CmdSpeak/App/CmdSpeakApp.swift` - remove local mode support
- `Sources/CmdSpeak/Core/Config/Config.swift` - simplify config, remove model type
- `Tests/` - remove WhisperKit and VAD tests
- `README.md` - update documentation
- `PRODUCT.md` - update status

---

## Deprecation Tasks (All Complete)

### Task 1: Remove WhisperKit dependency ✅
- [x] Remove WhisperKit from `Package.swift`
- [x] Remove `WhisperKitEngine.swift`

### Task 2: Remove local mode controller ✅
- [x] Remove `CmdSpeakController.swift`
- [x] Remove `VoiceActivityDetector.swift`

### Task 3: Simplify CLI ✅
- [x] Remove `run-local` command
- [x] Rename `run-openai` to `run` (make it the default)
- [x] Remove `run` command that auto-selects mode
- [x] Remove `test-transcribe` command (WhisperKit test)

### Task 4: Simplify menu bar app ✅
- [x] Remove local mode initialization path
- [x] Remove model type config handling
- [x] Always use OpenAI controller

### Task 5: Simplify config ✅
- [x] Remove `model.type` field (always openai-realtime)
- [x] Remove `model.name` for local models
- [x] Keep only OpenAI-relevant config

### Task 6: Clean up tests ✅
- [x] Remove VAD tests
- [x] Remove WhisperKit-related tests
- [x] Remove ModelLoadProgress tests
- [x] Update remaining tests (108 tests pass)

### Task 7: Update documentation ✅
- [x] Update README.md
- [x] Update PRODUCT.md
- [x] Remove WhisperKit sections

---

### Recently Closed
- #28 Homebrew distribution ✅
- #26 Menu bar app with visual feedback ✅
- #25 WhisperKit VAD ✅
- #24 WhisperKit streaming transcription ✅

---

## WhisperKit Local Mode (Complete)

### What We've Done ✅

1. **Fixed model name format**: The HuggingFace repo uses underscores, not hyphens
   - ❌ `openai_whisper-large-v3-turbo` (incorrect)
   - ✅ `openai_whisper-large-v3_turbo` (correct)

2. **Enabled ANE (Apple Neural Engine) acceleration**:
   - Added explicit `ModelComputeOptions` configuration
   - `audioEncoderCompute: .cpuAndNeuralEngine`
   - `textDecoderCompute: .cpuAndNeuralEngine`
   - `prewarm: true` for model specialization

3. **Performance results**:
   | Metric | Before Fix | After Fix |
   |--------|------------|-----------|
   | Model load (first run) | 247s | 135s (ANE compilation) |
   | Model load (cached) | 10s | 11s |
   | Transcription (3s audio) | 131s ❌ | 2.8s ✅ |
   | Real-time factor | 44x (CPU fallback) | ~1x (ANE) |

### Watch-outs ⚠️

1. **First-run ANE compilation takes ~2-4 minutes**
   - Core ML must "specialize" models for the device's Neural Engine
   - Cached after first run (stored by macOS, not by app)
   - Cache evicted after OS updates → recompilation required

2. **Model download is ~954MB**
   - Downloaded automatically on first use
   - Stored in `~/Library/Caches/WhisperKit/` (managed by WhisperKit)

3. **CLI context may not use ANE optimally**
   - Command-line tools may fall back to CPU in some cases
   - Menu bar app / GUI context typically gets better ANE utilization

4. **Model name format is fragile**
   - WhisperKit uses glob patterns to find models in HuggingFace
   - Incorrect names produce confusing "model not found" errors
   - Always check [argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml) for exact folder names

5. **Large models may not work on all devices**
   - `large-v3_turbo` requires ~2GB RAM during inference
   - Older devices may need smaller models (`base`, `small`)

### Next Steps 📋

1. ✅ **Integrate WhisperKit into main controller flow**
   - `cmdspeak run` now auto-selects mode based on `config.model.type`
   - `type = "local"` → WhisperKit local transcription
   - `type = "openai-realtime"` → OpenAI Realtime API streaming

2. ✅ **Add model download progress UI**
   - CLI shows progress bar with download percentage and MB count
   - Menu bar app shows progress indicator with status messages
   - Progress stages: Downloading → Downloaded → Loading → Compiling → Ready
   - First-run ANE compilation message warns about 2-4 min wait

3. ✅ **Fix polling async waits (P1 tech debt)**
   - Replaced with CheckedContinuation for proper async signaling
   - `waitForSessionReady()` and `awaitFinalTranscript()` fixed

---

4. ✅ **Homebrew formula**
   - Created `Formula/cmdspeak.rb` for Homebrew distribution
   - Created `Makefile` for standard build/install workflow
   - Users can install via `brew tap LxYuan0420/cmdspeak && brew install cmdspeak`

---

### Completed Features 🎉

**Phase 4: Distribution** ✅
- [x] Create `homebrew-cmdspeak` tap repository on GitHub (ready at ~/personal_works/homebrew-cmdspeak)
- [x] Create release tag `v0.1.0`
- [x] Homebrew formula for `brew install cmdspeak`

**Streaming Transcription for Local Mode** ✅
- [x] Show words as you speak instead of waiting for full audio
- [x] WhisperKit `TranscriptionCallback` provides incremental text during decoding
- [x] Display partial results in CLI (📝 prefix with live updates)
- [x] Display partial results in menu bar (same as OpenAI mode)
- [x] Accumulate and inject final text on stop
- Note: WhisperKit streaming shows words as they're decoded, not as you speak
  - Unlike OpenAI's real-time API which streams while recording
  - WhisperKit transcribes after recording stops, but shows progress during decoding

**Menu Bar App** ✅
- [x] Menu bar app with visual feedback (dynamic icons, color-coded status)
- [x] Live transcription preview while recording
- [x] Error messages with recovery hints
- [x] Model download progress bar

**Voice Activity Detection** ✅
- [x] Energy-based VAD in VoiceActivityDetector
- [x] Server VAD for OpenAI mode (speech_started/stopped events)
- [x] Configurable silence thresholds

**Tech Debt Cleared** ✅
- [x] Manual CMSampleBuffer loops → use AVAudioEngine tap
- [x] Stringly-typed JSON events → proper Codable structs
- [x] Polling async waits → CheckedContinuation

### Remaining Work 📋

**Distribution** (lower priority)
- [ ] DMG installer - drag-and-drop installation
- [ ] Code signing for Gatekeeper

**Onboarding** (Issue #27)
- [ ] System permissions onboarding flow
- [ ] Guide users through Accessibility + Microphone permissions

**Other Ideas**
- [ ] Test on different Mac hardware (M1/M2/M3/Intel)
- [ ] Add keyboard shortcut customization
- [x] Support multiple languages in same session ✅

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
- [x] 73 unit tests passing
- [x] Engine message handling tests
- [x] Multi-segment accumulation regression tests
- [x] PCM16 conversion tests
- [x] Configuration validation tests
- [x] AudioResampler tests
- [x] VAD callback tests
- [x] Error classification tests

---

## Known Issues 🐛

### High Priority
1. ~~**Unbounded Task creation for audio sends**~~ ✅ FIXED
   - Now uses bounded AsyncStream with 50-buffer limit
   - Single sender task processes queue sequentially

2. **Polling-based session/transcript waiting**
   - `waitForSessionReady()` and `awaitFinalTranscript()` poll every 50ms
   - Should use `CheckedContinuation` for proper async signaling

3. ~~**Naive audio resampling (nearest-neighbor)**~~ ✅ FIXED
   - Now uses AVAudioConverter with linear interpolation fallback

### Medium Priority
4. ~~**Silence detection based on transcription deltas, not audio**~~ ✅ FIXED
   - Now uses server VAD events (`speech_started`/`speech_stopped`)

5. ~~**Short final transcript timeout (1s)**~~ ✅ FIXED
   - Now uses 3s timeout

6. ~~**No explicit reconnecting state in UI**~~ ✅ FIXED
   - Now shows "Reconnecting (1/3)..." with yellow indicator and dedicated icon

### Low Priority
7. **Manual PCM buffer unpacking loops**
   - Inefficient; should use AVAudioEngine tap
8. **Base64 encoding overhead**
   - Could batch larger frames (50-100ms)
9. **No microphone device selection**

---

## Roadmap 🗺️

### Phase 1: Core Stability (Current) ✅
- [x] Multi-segment transcript fix
- [x] Session ID race condition fix
- [x] Reconnection with backoff
- [x] Menu bar app for background operation
- [x] Bounded audio send pipeline (AsyncStream with 50-buffer limit)
- [x] Increased final transcript timeout (1s → 3s)
- [x] **AVAudioConverter resampling** (with linear interpolation fallback)

### Phase 2: Reliability ✅
- [x] **Server VAD-based endpointing** (uses speech_started/stopped events)
- [x] **Error code classification** (fatal vs transient, stops retries on auth errors)
- [x] **Connection timeout enforcement** (10s timeout on WebSocket connection + session ready)
- [x] **Proper disconnect semantics** (DisconnectReason enum, cleanup sequencing)
- [x] **Telemetry hooks** (SessionMetrics, TelemetryAggregator, latency/drops/reconnects tracking)

### Phase 3: User Experience ✅
- [x] **Reconnecting state with UI feedback** (shows attempt count, yellow indicator, dedicated icon)
- [x] **Hotkey during connecting = cancel**
- [x] **Hotkey during reconnecting = cancel**
- [x] **Hotkey during finalizing = force inject** (immediately injects accumulated text)
- [x] **Live transcription preview in menu bar** (shows partial text while speaking)
- [x] **Clear error messages with recovery hints** (actionable error states)
- [x] **Opinionated defaults** - see design decision below

> **Design Decision: Opinionated Defaults**
>
> CmdSpeak is designed as a "just works" application. We deliberately chose NOT to implement:
> - **Microphone device selection** → Uses system default microphone. Users who need specific mics can set it in System Settings → Sound → Input.
> - **Input level indicator** → Adds visual clutter. The transcription preview provides sufficient feedback that audio is being captured.
> - **VAD threshold configuration** → Server VAD (OpenAI) and WhisperKit's built-in VAD work well with default thresholds. Exposing this creates confusion.
>
> This philosophy extends to model selection: we pick the best model for each mode and download it automatically.

### Phase 4: Distribution ✅
- [x] Homebrew formula (`Formula/cmdspeak.rb`)
- [x] Makefile for standard installation
- [x] Create homebrew-cmdspeak tap repository (ready at ~/personal_works/homebrew-cmdspeak)
- [x] Release tag v0.1.0
- [ ] Code signing for Gatekeeper
- [ ] DMG installer
- [ ] Auto-update mechanism

### Phase 5: Onboarding (In Progress)
- [ ] System permissions onboarding flow (Issue #27)
  - Clear instructions for Accessibility + Microphone permissions
  - Opens System Settings to correct pane
  - Detects when permissions are granted

---

## Technical Debt

| Issue | Impact | Effort | Priority | Status |
|-------|--------|--------|----------|--------|
| ~~Unbounded audio Task spawning~~ | High (memory/latency) | M (2-3h) | P0 | ✅ Done |
| ~~Nearest-neighbor resampling~~ | Medium (accuracy) | M (2-3h) | P0 | ✅ Done |
| ~~Polling async waits~~ | Medium (races) | M (2-3h) | P1 | ✅ Done |
| ~~Manual CMSampleBuffer loops~~ | Low (perf) | L (1-2d) | P2 | ✅ Done |
| ~~Stringly-typed JSON events~~ | Low (maintainability) | M (2-3h) | P2 | ✅ Done |

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
| OpenAI Realtime Engine | 19 | ✅ |
| PCM16 Conversion | 9 | ✅ |
| Message Handling | 15 | ✅ |
| Controller State | 8 | ✅ |
| Error Classification | 4 | ✅ |
| Config | 8 | ✅ |
| Hotkey Logic | 4 | ✅ |
| Audio Resampler | 5 | ✅ |
| VAD | 4 | ✅ |
| Connection Timeout | 3 | ✅ |
| Session Metrics | 4 | ✅ |
| Metrics Collector | 6 | ✅ |
| Telemetry Aggregator | 3 | ✅ |
| Model Load Progress | 4 | ✅ |
| **Total** | **96** | ✅ |

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

# Run CLI (auto-selects mode based on config.model.type)
.build/release/cmdspeak run

# Run with local WhisperKit (ignores config, forces local mode)
.build/release/cmdspeak run-local

# Run with OpenAI Realtime API (ignores config, forces openai-realtime mode)
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

### 2026-01-31
- **BREAKING: Deprecated local WhisperKit mode, OpenAI-only now**
  - Removed WhisperKit dependency (~1GB smaller)
  - Removed local mode controller, VAD, ModelLoadProgress
  - Simplified CLI: `cmdspeak` now runs OpenAI mode directly
  - Simplified config: removed `model.type`, always uses gpt-4o-transcribe
  - Simplified menu bar app: OpenAI controller only
  - 108 tests pass (down from 121, removed local mode tests)
- **Fixed: Audio format mismatch crash on recording restart**
  - Crash: "Input HW format and tap format not matching" when restarting recording
  - Root cause: `installTap` was called with `nil` format, which fails if hardware format changes
  - Fix: Call `engine.reset()` before setup and use actual `hwFormat` for tap
- **Fixed: OpenAI hallucination during silence**
  - OpenAI API was returning prompt text as transcription when user is silent
  - Added `hallucinationPatterns` filter to ignore prompt-like text in transcription deltas
- **Fixed: Local mode VAD processing wrong sample rate**
  - VAD was processing hardware sample rate (44.1kHz/48kHz) instead of resampled 16kHz
  - Added `processSamples(_ samples: [Float])` method to `VoiceActivityDetector`
  - Changed controller to pass resampled audio to VAD for correct silence detection
- **Verified: Local mode buffer and resampler working correctly**
  - Buffer cleared before each session, max duration timer prevents unbounded growth
  - AudioResampler correctly configured for 16kHz output

### 2026-01-28
- **Added: Streaming transcription for local WhisperKit mode**
  - Shows transcription progress during decoding (words appear as they're decoded)
  - CLI displays `📝 partial text...` with live updates
  - Menu bar app shows live transcription preview (same as OpenAI mode)
  - `WhisperKitEngine.transcribe(audioSamples:progressCallback:)` method
  - `CmdSpeakController.onPartialTranscription` and `onFinalTranscription` callbacks
- **Refactored: CmdSpeakController now uses AudioResampler**
  - Replaced manual nearest-neighbor resampling with AVAudioConverter-based resampler
  - AudioResampler now supports configurable target sample rate (16kHz for WhisperKit, 24kHz for OpenAI)
- **Refactored: OpenAI Realtime API messages now use proper Codable structs**
  - Created `OpenAIRealtimeMessages.swift` with typed request/response structs
  - Replaced JSONSerialization with JSONEncoder/JSONDecoder
  - Added `OpenAIEventType` enum for type-safe event handling
- **Refactored: AudioCaptureManager now uses AVAudioEngine**
  - Replaced AVCaptureSession + CMSampleBuffer with AVAudioEngine tap
  - No more manual buffer unpacking — AVAudioPCMBuffer provided directly
  - Simpler, more efficient, and the modern approach for audio capture
- **Added: Multi-language support with auto-detection**
  - Language auto-detected per utterance (99+ languages supported)
  - CLI shows detected language with 🌐 indicator
  - Menu bar app displays detected language
  - `onLanguageDetected` callback for UI integration
  - Config comments updated to emphasize auto-detect as default
- **Added: Release tag v0.1.0**
- **Added: Homebrew tap repository** (ready at ~/personal_works/homebrew-cmdspeak)
- **Added: Homebrew formula for distribution**
  - Created `Formula/cmdspeak.rb` for `brew install cmdspeak`
  - Created `Makefile` with build/install/uninstall/clean/test targets
  - Created `HOMEBREW.md` with tap setup instructions
  - Updated README with Homebrew installation instructions

### 2026-01-27
- **Added: Model download progress UI**
  - CLI shows progress bar: `[████████████░░░░░░░░░░░░░░░░░░] 40% Downloading: 380 / 954 MB`
  - Menu bar app shows linear progress indicator with status messages
  - `ModelLoadProgress` struct with stages: downloading, downloaded, loading, compiling, ready
  - First-run ANE compilation message warns users about 2-4 min wait
- **Added: Unified `cmdspeak run` command with auto mode selection**
  - Reads `config.model.type` to choose between local and openai-realtime modes
  - `type = "local"` → Uses WhisperKit for on-device transcription
  - `type = "openai-realtime"` → Uses OpenAI Realtime API for streaming
- **Fixed: Polling async waits replaced with CheckedContinuation** (P1 tech debt)
  - `waitForSessionReady()` now uses proper async signaling instead of polling
  - `awaitFinalTranscript()` now uses continuation-based waiting
  - Continuations properly cleaned up on disconnect to prevent leaks
- Added: `cmdspeak run-local` command (forces local mode regardless of config)
- Added: Menu bar app now supports both local and OpenAI modes based on config
- Added: Cancellation handling in WhisperKitEngine initialization
- Added: State reset on re-initialization to prevent stale state
- Refactored: `RunOpenAI` now delegates to shared `Run.runOpenAIMode()` (removed duplication)
- Refactored: Removed redundant main queue hop in hotkey callback
- Updated: README with comprehensive documentation
- Added: 4 new tests for `ModelLoadProgress`
- Total: 96 tests passing

### 2026-01-26
- **Fixed: WhisperKit local transcription performance** (was 131s, now 2.8s for 3s audio)
  - Added explicit `ModelComputeOptions` for ANE acceleration
  - Configured `audioEncoderCompute: .cpuAndNeuralEngine` for optimal performance
  - Added `prewarm: true` for ANE model specialization
- **Fixed: WhisperKit model name** (`openai_whisper-large-v3_turbo` - underscore not hyphen)
- Added: Connection timeout enforcement (10s timeout wrapping entire connection flow)
- Added: `TranscriptionError.connectionTimeout` error case
- Added: Reconnecting state with UI feedback (attempt count, yellow indicator, dedicated icon)
- Added: Hotkey during reconnecting now cancels reconnection
- Added: Hotkey during finalizing now force-injects accumulated text immediately
- Added: Live transcription preview in menu bar (📝 prefix, shows "Listening..." when empty)
- Added: Clear error messages with recovery hints (💡 actionable guidance)
- Added: Dismiss Error button in menu bar
- Added: Finalizing state now shows purple indicator and "Injecting..." status
- Added: **Phase 2 Reliability complete:**
  - `DisconnectReason` enum for proper disconnect semantics
  - `SessionMetrics` struct tracking connection latency, drops, reconnects, duration
  - `SessionMetricsCollector` for per-session metric collection
  - `TelemetryAggregator` actor for cross-session aggregation
  - `onSessionMetrics` callback on controller for external telemetry integration
- Added: **Phase 3 UX complete** with opinionated defaults decision
- Updated: WhisperKit default model changed to `large-v3_turbo` for best quality
  - 954MB download (vs 3GB for Large-V3)
  - Near-Large-V2 accuracy with ~1x realtime inference on ANE
  - 4 decoder layers optimized for Apple Neural Engine
- Added: RTF (Real-Time Factor) logging for WhisperKit transcription
- Added: 13 telemetry tests (SessionMetrics, Collector, Aggregator)
- Total: 92 tests passing

### 2026-01-24
- Added: AVAudioConverter-based resampling with linear interpolation fallback
- Added: Server VAD-based endpointing (speech_started/stopped events)
- Added: Error code classification (fatal vs transient errors)
- Added: Hotkey during connecting now cancels connection
- Added: AudioResampler tests, VAD callback tests, error classification tests
- Improved: Silence timer now driven by server VAD, not transcription deltas
- Improved: Fatal errors (auth, quota, model) stop retry attempts immediately
- Total: 73 tests passing

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
