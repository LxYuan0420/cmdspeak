# CmdSpeak TODO

## Bug Fixes (Completed 2026-01-21)

- [x] Fixed hotkey → audio → transcription flow
  - Root cause: `CFRunLoopRun()` doesn't process `DispatchQueue.main.async` blocks
  - Solution: Use `RunLoop.current.run(until:)` in a loop instead
  - Also fixed event tap registration using `CFRunLoopGetMain()` instead of `CFRunLoopGetCurrent()`

- [x] Fixed TOMLKit config parsing
  - Root cause: `table["key"] as? Type` doesn't work, need `table["key"]?.type` accessors
  - Solution: Use `.table`, `.string`, `.bool`, `.int` property accessors

- [x] Added translation support
  - New config option: `translate_to_english = true`
  - Uses WhisperKit's `DecodingOptions(task: .translate)`

- [x] Added test commands for debugging
  - `test-mic` - Test microphone capture
  - `test-hotkey` - Test hotkey detection
  - `test-transcribe` - Test model + transcription
  - `test-integration` - Test full pipeline

## Future Work

### High Priority

- [ ] **Real-time streaming transcription**
  - Show partial results as user speaks
  - Use WhisperKit streaming API or chunked processing
  - Display intermediate text in terminal/UI

- [ ] **Voice Activity Detection (VAD) auto-stop**
  - Currently requires manual double-tap to stop
  - Implement silence detection to auto-stop after speech ends
  - Configurable silence threshold

- [ ] **Better error handling**
  - Graceful recovery from audio device disconnection
  - Handle model loading failures with retry

### Medium Priority

- [ ] **Menu bar app improvements**
  - Visual feedback (waveform) during recording
  - Show transcription status
  - Quick access to settings

- [ ] **Configurable hotkey**
  - Allow users to choose their own hotkey
  - Support other modifier keys (Ctrl, Cmd, etc.)

- [ ] **Larger model support**
  - `openai_whisper-large-v3-turbo` for better accuracy
  - Model download progress indicator
  - Model switching without restart

- [ ] **Per-app profiles**
  - Different settings for different apps
  - Auto-detect focused app

### Low Priority

- [ ] **Homebrew distribution**
  - Create Homebrew tap
  - Build DMG for direct download

- [ ] **Language auto-switching**
  - Detect language changes mid-session
  - Show detected language in output

- [ ] **Punctuation improvements**
  - Better sentence boundaries
  - Configurable punctuation style

## Known Issues

- AVCaptureDevice warning about `AVCaptureDeviceTypeExternal` deprecation (cosmetic only)
- First transcription after model load may be slower (model warmup)

## Notes

- Tested on macOS 15.6.1 (Sequoia) with Apple Silicon
- WhisperKit model: `openai_whisper-base` (~150MB)
- Translation works for 90+ languages → English
