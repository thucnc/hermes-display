# Global AGENTS.md — Standards for Autonomous Coding Agents

Universal code quality and engineering guidelines for Hermes Display (Huawei MatePad Client).

---

## 1. Core Invariants
- **Model**: Claude Opus 5.5 (`--model opus`).
- **No Magic Numbers/Strings**: Luôn khai báo `const` hoặc `enum`.
- **Early Return & Flat Nesting**: Guard clauses ở đầu hàm.
- **Concise Function Names**: Tối đa 30 ký tự.
- **Minimal Blast Radius**: Chỉ sửa các file trong phạm vi task.
- **Always Braced**: Luôn dùng `{}` cho các khối điều khiển.
- **Flutter Standards**: Tách biệt Controller/Service/UI rõ ràng, `flutter analyze` 0 issues.
- **Android Target**: Huawei MatePad (HarmonyOS/AOSP, no GMS), hỗ trợ Always-on WAKE_LOCK, xử lý microphone permission an toàn.
