# Hermes Display (Ambient Smart Display for Huawei MatePad)

Hermes Display là client Flutter biến tablet (đặc biệt là Huawei MatePad HarmonyOS/AOSP) thành **Trạm hiển thị & Điều khiển thông minh (Ambient Smart Display)** kết nối trực tiếp với **Hermes Agent Hub** trên Mac mini M4.

Được thiết kế và implement hoàn toàn bởi **Claude Opus 5.5**.

---

## 🌟 Tính năng chính

1. **Always-On & Ambient Display:**
   - Trình chiếu ảnh thông minh (Cross-fade slideshow) khi không sử dụng.
   - Đồng hồ, ngày tháng, thời tiết, status indicator thời gian thực.
   - Giữ màn hình luôn sáng (`WAKE_LOCK`).

2. **Hands-free Voice Interaction:**
   - Wake Word: **"Hey Sen"** kích hoạt chế độ lắng nghe tức thì.
   - Pipeline âm thanh tương tác 2 chiều với `hermes-voice-bridge` trên Mac mini M4.
   - Visualizer sóng âm thanh sống động lúc đang nghe và phản hồi.

3. **Hybrid Local AI (On-Device STT/TTS):**
   - Tích hợp `sherpa_onnx` để chạy Zipformer STT tiếng Việt và Piper TTS tiếng Việt offline 100% trên tablet.

4. **Tự động Cập nhật Không Cần Chplay (OTA Auto-Update):**
   - Tự động kiểm tra GitHub Releases (`thucnc/hermes-display`).
   - Tự tải APK bản mới nhất và trigger intent cài đặt trên Huawei EMUI/HarmonyOS.

---

## 🏗️ Kiến trúc Hệ thống

```
[ Huawei MatePad (Client) ]
   ├── Screen: Ambient Slideshow + Clock / Status Overlay
   ├── Wake Word: "Hey Sen" (Offline)
   ├── Local STT/TTS: Sherpa-ONNX Zipformer + Piper (Offline Tiếng Việt)
   └── UI State: IDLE ⇄ LISTENING ⇄ THINKING ⇄ SPEAKING
         │
         ▼ (WebSocket / LAN or Tailscale)
[ Mac mini M4 (Hermes Agent Hub) ]
   ├── hermes-voice-bridge (:8900)
   ├── Hermes Brain (LLM + Context + Tools)
   └── Audio Pipeline Fallback
```

---

## 🎙️ Wake Word Model

Wake word chạy offline bằng sherpa-onnx KWS
(`sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01`, tiếng Anh).

**Tự cài đặt:** lần chạy đầu app tải 4 file (~6 MB) từ ModelScope
(`encoder…int8.onnx`, `decoder….onnx`, `joiner…int8.onnx`, `tokens.txt`).
Mỗi file được kiểm tra độ dài + SHA-256, tải vào `files/kws.installing/`,
chỉ đổi tên thành `files/kws/` khi tất cả hợp lệ, kèm marker
`installed.version`. Mỗi lần khởi động app băm lại toàn bộ trước khi dùng;
thư mục thiếu marker / sai version / sai hash bị bỏ qua và tải lại.
Trạng thái + nút "Thử lại" nằm trong Cài đặt → "Model từ khoá".
Chưa có model: app vẫn chạy, nút micro vẫn ghi âm và stream lên Hub.
Không có mirror HuggingFace (repo không truy cập được để xác minh hash).

**Từ khoá:** model không kèm tokenizer, `keywords.txt` được sinh từ
`tokens.txt` bằng greedy longest-match SentencePiece:

```
HEY SEN  →  ▁HE Y ▁SE N @HEY_SEN
```

- Chuỗi trên khớp output `sentencepiece` thật trên `bpe.model` của model
  (đã kiểm tra lúc phát triển). Với từ khác, greedy chỉ khớp ~70% từ tiếng Anh.
- Chỉ chữ A–Z, `'` và khoảng trắng; không dấu tiếng Việt. Cài đặt từ chối từ
  khoá không tokenize được.
- Độ nhạy 0..1 → threshold 0.9..0.2; `keywordsScore` 1.5;
  `numTrailingBlanks` 3 (giới hạn 1..5).

**Luôn lắng nghe (mặc định BẬT):** foreground service
`MicKeepAliveService` (`foregroundServiceType=microphone`, thông báo mức
thấp, partial wake lock) giữ quyền ghi âm khi tắt màn hình / app nền. Luồng
micro vẫn chạy trong Flutter engine; vuốt tắt app khỏi Recents sẽ dừng.
Wake word và lượt hội thoại dùng chung `MicCoordinator`: wake word nhả micro
trước khi ghi lượt nói, lấy lại khi lượt kết thúc hoặc bị huỷ.

### Huawei EMUI / HarmonyOS

EMUI vẫn kill app nền dù có foreground service. Cấu hình thủ công:

1. Cài đặt → Pin → Khởi chạy ứng dụng → Hermes Display → tắt
   "Quản lý tự động", bật cả 3: Tự khởi chạy, Khởi chạy phụ, Chạy nền.
2. Cài đặt → Pin → tắt chế độ tiết kiệm pin cho app (nếu có).
3. Tuỳ chọn nhà phát triển → "Không khoá màn hình khi sạc" (Stay awake).
4. Cho phép thông báo của app (Android 13+ sẽ hỏi lần đầu).

### Đã kiểm chứng / chưa kiểm chứng

- Unit test: installer (fake HTTP), tokenizer (gồm `tokens.txt` thật),
  mic lease hand-off, background mode, Settings.
- Debug APK build thành công (Kotlin service biên dịch).
- **Chưa kiểm chứng:** nhận diện "Hey Sen" trên giọng nói thật, service chạy
  trên MatePad thật khi tắt màn hình, tải model qua mạng thật trên thiết bị.

Giao thức audio: sau `{"type":"wake"}` client gửi binary frame PCM16 LE mono 16 kHz,
kết thúc bằng `{"type":"audio_end"}` (hoặc `{"type":"cancel"}`).

## 🚀 Cài đặt & Build

```bash
flutter pub get
flutter build apk --release
```
File APK sẽ xuất hiện tại: `build/app/outputs/flutter-apk/app-release.apk`
