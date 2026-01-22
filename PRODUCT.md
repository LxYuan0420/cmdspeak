# CmdSpeak Product Specification

## Vision

CmdSpeak is a **drop-in replacement for macOS Dictation** that uses modern speech-to-text models. Same gesture (double-tap), same universality (works everywhere), but with better transcription quality.

## Core User Experience

### Target UX (matches macOS Dictation)
1. **Trigger**: Double-tap Right Option key
2. **Listening**: Audio indicator shows recording is active
3. **Transcription**: Text appears at cursor position in real-time
4. **Auto-stop**: After ~2s of silence, recording stops and text is injected
5. **Cancel**: Double-tap again to cancel without injecting

### Key Differences from macOS Dictation
- Uses OpenAI or open-source models (user choice)
- Supports multiple languages with better accuracy
- Works offline with local models
- Configurable silence threshold

---

## Workstream 1: OpenAI Realtime API

Uses OpenAI's Realtime Transcription API for streaming speech-to-text.

### Task 1.1: Fix WebSocket Stability
**Goal**: Reliable connection that doesn't drop during long recordings  
**Current Issue**: Auto-stops after ~60s or on connection issues  
**Verification**: Record for 2+ minutes without interruption

### Task 1.2: Reduce Latency
**Goal**: First transcription within 500ms of speech  
**Current Issue**: ~1-2s delay before first words appear  
**Verification**: Measure time from speech start to first character

### Task 1.3: Improve Silence Detection
**Goal**: Auto-inject after 2s silence (not 5s)  
**Current Issue**: 5s feels too long, breaks flow  
**Verification**: Natural pause between sentences doesn't trigger injection

### Task 1.4: Multilingual Support
**Goal**: Seamless switching between languages mid-sentence  
**Current Issue**: Language detection may be inconsistent  
**Verification**: Speak English + Mandarin in same session

### Task 1.5: Visual Feedback
**Goal**: Menu bar indicator shows recording state  
**Current Issue**: CLI-only feedback  
**Verification**: User can see recording status without terminal

---

## Workstream 2: Open Source Models (WhisperKit)

Uses local WhisperKit for offline, privacy-first transcription.

### Task 2.1: Model Loading Performance
**Goal**: Model ready within 5s of app launch  
**Current Issue**: Slow first load, no progress indicator  
**Verification**: Time from launch to "Ready" state

### Task 2.2: Streaming Transcription
**Goal**: Show partial text as user speaks  
**Current Issue**: Batch-only (waits for full audio)  
**Verification**: Text appears incrementally during speech

### Task 2.3: Voice Activity Detection (VAD)
**Goal**: Auto-stop after speech ends  
**Current Issue**: Requires manual double-tap to stop  
**Verification**: Recording stops automatically after 2s silence

### Task 2.4: Larger Model Support
**Goal**: Support whisper-large-v3-turbo for better accuracy  
**Current Issue**: Only tested with base model  
**Verification**: Compare accuracy between models

### Task 2.5: Memory Optimization
**Goal**: App uses <500MB memory during transcription  
**Current Issue**: Unknown memory footprint  
**Verification**: Monitor memory during 5-minute recording

---

## Shared Tasks

### Task S.1: Menu Bar App
**Goal**: Native macOS menu bar app with recording indicator  
**Current Issue**: CLI-only interface  
**Verification**: App runs from menu bar, shows status

### Task S.2: System Permissions Flow
**Goal**: Smooth onboarding for Accessibility + Microphone  
**Current Issue**: No guided setup  
**Verification**: New user can get running in <1 minute

### Task S.3: Configuration UI
**Goal**: Preferences window for model, hotkey, silence threshold  
**Current Issue**: TOML config only  
**Verification**: Change settings without editing files

### Task S.4: Homebrew Distribution
**Goal**: `brew install cmdspeak`  
**Current Issue**: Build from source only  
**Verification**: Fresh macOS can install via brew

---

## Success Criteria

CmdSpeak is successful when:
1. ✅ User can dictate in any app (browser, IDE, email)
2. ✅ Double-tap gesture matches muscle memory from macOS Dictation
3. ✅ Transcription quality beats Apple's built-in dictation
4. ✅ Works offline with local models (optional)
5. ✅ No cloud account required for basic usage

---

## Technical Notes

### Audio Format Requirements
- OpenAI Realtime: 24kHz PCM16 mono
- WhisperKit: 16kHz Float32 mono

### Hotkey
- Default: Right Option double-tap (keycode 61)
- Configurable via config.toml

### Text Injection
- Uses macOS Accessibility API (AXUIElement)
- Fallback to clipboard paste if needed
