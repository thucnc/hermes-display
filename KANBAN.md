# Hermes Display Kanban Board

Last Updated: 2026-10-02

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

- [ ] **KB-006**: Album ảnh từ Immich / NAS (local folder + Apple Photos xong ở KB-015)
  - Priority: Low
  - Assignee: claude-code (opus-5-5)
  - Tags: #slideshow

## In Progress

## Review

- [ ] **KB-014**: Auto Update — APK OTA & tự làm mới Knowledge Pack
  - Priority: High
  - Assignee: claude-code (opus-5-5)
  - Completed: 2026-10-02
  - Tests: 282/282 (257 cũ + 25 mới), 0 analyze issues, release APK builds (versionCode/versionName từ `--build-number`/`--build-name`). Hub: 29 + publish 3 + exporter 7 + save 11 Python tests.
  - Pack: refresh mỗi 30 phút, khi app resume (ambient wake) và khi Hub đẩy `pack_updated` (Hub poll hash `Sen/` mỗi 10s); các lần gọi chồng nhau dùng chung một request.
  - OTA: `AppUpdater` kiểm tra `GET /api/app/latest` (Hub hoặc URL tuỳ chỉnh trong Cài đặt) lúc mở app + mỗi đêm trong khung giảm sáng, tải APK vào cache, kiểm SHA-256, nhãn "Đã có bản cập nhật vX — Chạm để cài đặt", cài qua FileProvider + `ACTION_VIEW`; `UpdateReceiver` (`MY_PACKAGE_REPLACED`) mở lại app.
  - Ký & phiên bản: `android/key.properties` → signingConfig release; CI dùng tag + `run_number` và secrets keystore; `scripts/release.sh` + `docs/RELEASE.md`.
  - Hub: `GET /api/app/latest`, `GET /api/app/apk/<file>`, `tools/publish_apk.py`.
  - Unverified: cài đè thật trên MatePad/emulator; tự mở lại sau update trên Android 10+ cần app là Home mặc định hoặc quyền "Hiển thị trên ứng dụng khác".
  - Tags: #ota #auto-update #knowledge-pack

- [ ] **KB-015**: Khung ảnh gia đình (Local folder / Apple Photos manifest) & "Ngày này năm xưa"
  - Priority: High
  - Assignee: claude-code (opus-5-5)
  - Completed: 2026-10-02
  - Tests: 312/312 (257 cũ + 55 mới), 0 analyze issues. Hub/exporter: 7 endpoint + 17 exporter Python tests.
  - Manifest: `PhotoManifest`/`FamilyPhoto` (url tương đối theo manifest, bỏ mục lỗi, từ chối manifest rỗng), `PhotoManifestService` (ETag/304, cache theo URL cho offline boot).
  - Frame: `PhotoFrame` (playlist: ngày này năm xưa → ảnh của thành viên đang chọn → còn lại; đổi thứ tự lúc nửa đêm; tự kiểm tra manifest mỗi giờ; bỏ qua ảnh tải lỗi), `PhotoCache` (đĩa, LRU 300MB), `PhotoCaption` (huy hiệu "Ngày này năm xưa").
  - Gemini: câu hỏi về ảnh ("ảnh này chụp ở đâu?") kèm chú thích/địa điểm/ngày chụp/người trong ảnh đang hiển thị.
  - Hub: `tools/export_photos.py` (folder + EXIF DateTimeOriginal, osxphotos album/Shared Album, WebP 1080p + thumb, xoá EXIF/GPS) và `GET /api/photos/manifest` + `/api/photos/{img|thumb}/<id>.webp` trên `display_hub.py`.
  - Unverified: trên MatePad thật; adapter osxphotos chỉ test với DB giả; HEIC qua `sips` chưa chạy thật.
  - Tags: #slideshow #photos #on-this-day #offline

- [ ] **KB-013**: Dynamic Sen Knowledge Pack qua URL công khai (Remote Sync)
  - Priority: High
  - Assignee: claude-code (opus-5-5)
  - Completed: 2026-10-02
  - Tests: 257/257 (215 cũ + 42 mới), 0 analyze issues. Hub/exporter: 32/32 + 7/7 Python tests.
  - Pack: `SenPack` (members/skills/rituals, camelCase hoặc snake_case, bỏ mục lỗi, từ chối pack rỗng), `SenPackRegistry` (thành viên động, skill/ritual theo trigger, `{{member.*}}`).
  - Service: `SenPackService.fetchAndApply` (timeout 10s, ETag/304, hash), cache SharedPreferences cho offline boot, upsert members + facts vào SQLite (schema v2, cột `source`).
  - Settings: `knowledgePackUrl` + nút "Đồng bộ ngay" có trạng thái; boot dùng cache rồi tự refresh.
  - Hub: `tools/export_sen_pack.py` (Sen/ → sen-pack.json) và `GET /api/sen/pack` trên `display_hub.py`.
  - Unverified: trên MatePad thật; avatar trong pack chưa hiển thị (vẫn dùng chữ cái).
  - Tags: #sen-os #knowledge-pack #remote-sync #offline

- [ ] **KB-011**: Sen OS — Member Profiles (Avatar Switcher), SQLite Memory Engine (Mem0-lite), & Pluggable Skills (Quiz & English Roleplay)
  - Priority: Critical
  - Assignee: claude-code (opus-5-5)
  - Completed: 2026-10-02
  - Tests: 215/215 (181 cũ + 34 mới), 0 analyze issues, debug APK builds.
  - Members: `MemberProfile` (Bố Thức / Mẹ / Bé), `MemberSwitcher` top-center, `activeMemberId` lưu trong SharedPreferences.
  - Memory: `SqfliteSenMemoryService` (members, facts, skill_progress), seed facts cho Bố Thức, `buildMemoryPrompt` ≤600 ký tự, prepend vào system instruction của Gemini.
  - Skills: `QuizSkill` (JSON 4 lựa chọn, `QuizCard` xanh/đỏ, trả lời bằng chạm hoặc giọng nói "đáp án B"), `EnglishRoleplaySkill` (theo `EnglishLevel`, `RoleplayCard`); skill giữ qua các lượt tới khi trả lời thường hoặc đóng thẻ.
  - Unverified: Gemini thật trả JSON đúng định dạng, SQLite trên MatePad thật.
  - Tags: #sen-os #memory #skills #quiz #english-roleplay #sqlite

- [ ] **KB-010**: Inline YouTube player trong RichCard, định tuyến Voice sang Gemini và TTS cho câu trả lời của Gemini
  - Priority: Critical
  - Assignee: claude-code (opus-5-5)
  - Completed: 2026-10-02
  - Tests: 181/181 (170 cũ + 11 mới), 0 analyze issues, debug APK builds.
  - Client: `InlineVideo` with embedded `youtube_player_flutter` inside `RichCard` (no external app jump, stays in kiosk).
  - Voice routing: when `activeBrain == BrainMode.gemini`, `audio_end` sends `brain: "gemini"`, Hub skips `run_hermes`, transcript triggers `_askGemini`.
  - Spoken summary: `SpokenSummary` cleans markdown and extracts 1-2 sentences for `HubTtsService` to speak via `TtsPlayer`.
  - Hub: `display_hub.py` handles `brain: "gemini"` by acknowledging transcript without blocking on `run_hermes`.
  - Tags: #youtube-inline #voice-gemini #tts #kiosk

- [ ] **KB-009**: Tích hợp Gemini 3.8 Flash Direct + Google Search Grounding, Rich Media Cards (YouTube/Recipe), và Save-to-Hermes Sync
  - Priority: Critical
  - Assignee: claude-code (opus-5-5)
  - Completed: 2026-10-02
  - Tests: 170/170 (141 cũ + 29 mới), 0 analyze issues, debug APK builds.
  - Client: `GeminiService` (Google Search grounding, YouTube videoId parser), `RichCard` (YouTube preview + Recipe steps), `HermesSyncService` (save to Obsidian).
  - Hub: `/save` endpoint on `bridge.py` & `display_hub.py` saves to `~/Documents/codebase/second-brain/Knowledge/<Category>/<Title>.md`. 11/11 tests pass.
  - Settings: Brain mode toggle (`Hub` vs `Gemini Direct`) + obscured `geminiApiKey`.
  - Tags: #gemini #youtube #recipe #grounding #second-brain

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
