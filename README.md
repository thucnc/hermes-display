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

## 🚀 Cài đặt & Build

```bash
flutter pub get
flutter build apk --release
```
File APK sẽ xuất hiện tại: `build/app/outputs/flutter-apk/app-release.apk`
