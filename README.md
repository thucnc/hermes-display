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

Wake word chạy offline bằng sherpa-onnx KWS. Model không đi kèm APK; giải nén
một model streaming transducer KWS (vd. `sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01`)
vào thư mục `<app support>/kws/` (`/data/user/0/com.hermes.display.hermes_display/files/kws/`):

- `encoder*.onnx`, `decoder*.onnx`, `joiner*.onnx` (ưu tiên bản `.int8.onnx`), `tokens.txt`
- `bpe.vocab` để dùng từ khoá tự do trong Cài đặt, hoặc `keywords.txt` đã tokenize sẵn

Thiếu model: app vẫn chạy, nút micro vẫn ghi âm và stream lên Hub.

Giao thức audio: sau `{"type":"wake"}` client gửi binary frame PCM16 LE mono 16 kHz,
kết thúc bằng `{"type":"audio_end"}` (hoặc `{"type":"cancel"}`).

## 🚀 Cài đặt & Build

```bash
flutter pub get
flutter build apk --release
```
File APK sẽ xuất hiện tại: `build/app/outputs/flutter-apk/app-release.apk`
