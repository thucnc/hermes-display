# Hermes Display Kanban Board

Last Updated: 2026-10-01 14:45

## Backlog

- [ ] **KB-003**: Cấu hình OTA Auto-Update Service kết nối GitHub Releases
  - Priority: High
  - Assignee: claude-code (opus-5-5)
  - Tags: #ota #auto-update

- [ ] **KB-004**: Tích hợp `sherpa_onnx` Zipformer STT Tiếng Việt streaming on-device
  - Priority: High
  - Assignee: claude-code (opus-5-5)
  - Tags: #stt #offline #sherpa-onnx

- [ ] **KB-005**: Tích hợp Piper TTS Tiếng Việt on-device
  - Priority: Medium
  - Assignee: claude-code (opus-5-5)
  - Tags: #tts #piper #offline

- [ ] **KB-006**: Album ảnh từ Immich / NAS / Local storage
  - Priority: Low
  - Assignee: claude-code (opus-5-5)
  - Tags: #slideshow

## In Progress

## Review

- [ ] **KB-008**: Hub-side TTS streaming & audio playback on client, wake-word threshold tuning & visual mic indicator
  - Priority: Critical
  - Assignee: claude-code (opus-5-5)
  - Completed: 2026-10-02
  - Tests: 141/141 (126 cũ + 15 mới), 0 analyze issues, debug APK builds.
  - Hub: synthesized speech via `bridge.run_tts()` in executor, base64 MP3 in `tts` message. 11/11 tests pass.
  - Client: `TtsPlayer` (`audioplayers` BytesSource), `SpeechMessage.audioBytes`, stops on interrupt/cancel, auto-idle on complete.
  - Wake-word: default sensitivity 0.8, threshold ~0.10.
  - UI: `StatusBadge` mic indicator (armed = green, manual = grey, unavailable = orange).
  - Unverified: real audio playback on MatePad hardware, self-trigger when reply contains "Sen".
  - Tags: #tts #audio #wakeword #ux

- [ ] **KB-007**: Giảm sáng ban đêm & bật màn hình khi gọi "Hey Sen"
  - Priority: Medium
  - Assignee: claude-code (opus-5-5)
  - Completed: 2026-10-01
  - Tests: 126/126 (95 cũ + 31 mới), 0 analyze issues, debug APK builds.
  - Emulator API 34: window brightness override 0.05 trong khung giờ,
    NaN ngoài khung giờ / sau khi chạm.
  - Unverified: wake screen trên lock screen (emulator & MatePad thật),
    giảm sáng trên HarmonyOS.
  - Tags: #display #dimming #wakeword

- [ ] **KB-002**: Wake Word Sherpa KWS "Hey Sen" & voice capture pipeline
  - Priority: High
  - Assignee: claude-code (opus-5-5)
  - Completed: 2026-10-01
  - Tests: 46/46 unit & widget tests passed, 0 analyze issues, debug APK builds.
  - KB-002b: model auto-installer (SHA-256 pinned, atomic), "HEY SEN" →
    `▁HE Y ▁SE N`, mic lease hand-off, microphone foreground service,
    "Luôn lắng nghe" toggle. Tests 93/93.
  - Unverified: detection on real speech, screen-off on a real MatePad.
  - Tags: #wakeword #hey-sen #voice

- [ ] **KB-001**: Kiến trúc Scaffolding, State Machine, Ambient Slideshow UI & WebSocket Client
  - Priority: Critical
  - Assignee: claude-code (opus-5-5)
  - Completed: 2026-10-01 15:05
  - Commit: `adc6b13`
  - Tests: 24/24 unit & widget tests passed, 0 analyze warnings.
  - Tags: #flutter #ui #architecture #opus

## Done

- [x] **KB-000**: Khởi tạo repository & GitHub Action CI Android release
  - Completed: 2026-10-01 14:45
