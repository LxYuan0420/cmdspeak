# Hotkey Debug Checklist

**Date**: 2026-01-21  
**Status**: ✅ RESOLVED

## Summary

The hotkey detection issue has been resolved. The app now uses **Right Option** (keycode 61) as the trigger key to avoid conflicts with macOS keyboard shortcuts.

## Completed Tasks

- [x] Fixed hotkey from Right Command to Right Option (avoids macOS shortcut conflicts)
- [x] Fixed audio capture - replaced AVAudioEngine with AVCaptureSession (works with Bluetooth devices)
- [x] Fixed model name - use `openai_whisper-base` (correct WhisperKit model name)
- [x] Fixed audio format conversion - properly handle Int16/Int32/Float32 formats
- [x] Added sample rate resampling - downsample from 48kHz to 16kHz for WhisperKit
- [x] Verified double-tap detection logic works correctly
- [x] Verified callback chain is properly set up
- [x] Updated all CLI messages and documentation

## Configuration

Current defaults:
- **Hotkey**: `double-tap-right-option` (keycode 61)
- **Model**: `openai_whisper-base` (~150MB, fast)
- **Interval**: 300ms between taps
- **Silence threshold**: 500ms

## Files Modified

- `Sources/CmdSpeak/Core/Hotkey/HotkeyManager.swift` - hotkey detection
- `Sources/CmdSpeak/Core/Audio/AudioCaptureManager.swift` - AVCaptureSession-based capture
- `Sources/CmdSpeak/Core/Config/Config.swift` - default config values
- `Sources/CmdSpeak/CLI/CmdSpeakCLI.swift` - CLI messages
- `Sources/CmdSpeak/App/CmdSpeakApp.swift` - App UI messages
- `README.md` - documentation

## Future Improvements

- [ ] Add visual feedback (waveform) in menu bar during recording
- [ ] Support configurable hotkey (not just Right Option)
- [ ] Add streaming partial transcription display
- [ ] Support larger models for better accuracy (openai_whisper-large-v3_turbo)
- [ ] Add language auto-detection display
