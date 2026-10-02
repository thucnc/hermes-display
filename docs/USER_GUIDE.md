# 📘 Hướng dẫn Sử dụng Hermes Display & Sen OS

Phiên bản tài liệu: `v0.5.0` · Cập nhật: 2026-10-02

## Mục lục
1. [Giới thiệu tổng quan](#1-giới-thiệu-tổng-quan)
2. [Cài đặt & Triển khai từ A-Z](#2-cài-đặt--triển-khai-từ-a-z)
3. [Cấu hình & Sử dụng các Tính năng](#3-cấu-hình--sử-dụng-các-tính-năng)
4. [Tự tạo Kỹ năng & Tùy biến bằng Obsidian](#4-tự-tạo-kỹ-năng--tùy-biến-bằng-obsidian)
5. [Khắc phục sự cố & FAQ](#5-khắc-phục-sự-cố--faq)

---

## 1. Giới thiệu tổng quan

**Hermes Display** biến tablet gia đình thành **Trạm hiển thị thông minh (Ambient Smart Display)**: lúc rảnh trình chiếu ảnh + đồng hồ, khi được gọi thì nghe, trả lời và hiển thị thẻ nội dung. Tối ưu cho **Huawei MatePad (HarmonyOS/EMUI, không GMS)**, chạy được trên AOSP và tablet Android bất kỳ.

**Sen OS** là lớp "người bạn gia đình" bên trong app: **Bé Sen** biết đang nói chuyện với ai (Bố Thức / Mẹ / Bé), nhớ thói quen từng người và có kỹ năng riêng (đố vui, luyện tiếng Anh).

### Luồng hoạt động

```
"Hey Sen" (wake word on-device, sherpa-onnx KWS)
   ➔ Ghi âm câu hỏi ➔ Hub trên Mac mini nhận diện giọng nói (STT)
   ➔ Gemini 3.8 Flash Direct + Google Search Grounding (gọi thẳng từ tablet)
   ➔ Thẻ kết quả: YouTube Inline Player · Recipe Checklist · Đố vui · Roleplay
   ➔ Hub đọc to câu trả lời (TTS)
   ➔ "💾 Lưu vào Hermes" ➔ Obsidian Second Brain trên Mac mini
```

| Thành phần | Chạy ở đâu | Cần mạng? |
|---|---|---|
| Wake word "Hey Sen" | Tablet | Không (chỉ tải model lần đầu) |
| Nhận diện giọng nói (STT) | Hub (Mac mini, `hermes-voice-bridge` :8900) | LAN / Tailscale |
| Trả lời (Gemini 3.8 Flash) | Google API, gọi trực tiếp từ tablet | Internet |
| Trả lời (chế độ Hub) | Hermes Agent trên Mac mini | LAN / Tailscale |
| Đọc to (TTS) | Hub | LAN / Tailscale |
| Trí nhớ thành viên | SQLite trên tablet | Không |
| Lưu ghi chú | Hub → Obsidian vault | LAN / Tailscale |

> Gõ chữ (biểu tượng bàn phím) + chế độ Gemini hoạt động **không cần Hub**. Giọng nói và đọc to **cần Hub**.

---

## 2. Cài đặt & Triển khai từ A-Z

### 2.1. Yêu cầu thiết bị
- Tablet Android **9 trở lên** (khuyến nghị Huawei MatePad).
- Micro hoạt động, Wi-Fi ổn định.
- Nên cắm sạc thường trực (app giữ màn hình sáng).
- Mac mini (hoặc máy Mac bất kỳ) chạy **Hermes Agent Hub** cùng mạng LAN hoặc cùng Tailscale.

### 2.2. Tải APK
1. Trên tablet, mở trình duyệt: `https://github.com/thucnc/hermes-display/releases`.
2. Chọn bản mới nhất **`v0.5.0`** → tải `app-release.apk`.
3. Mở file vừa tải → cho phép **"Cài đặt ứng dụng không rõ nguồn gốc"** cho trình duyệt khi được hỏi → **Cài đặt**.

### 2.3. Cấp quyền trên Huawei EMUI / HarmonyOS
EMUI rất mạnh tay trong việc tắt app chạy nền. Làm **đủ cả 5 bước**:

| # | Đường dẫn | Thao tác |
|---|---|---|
| 1 | Mở app lần đầu | Chọn **Cho phép** quyền **Micro** và **Thông báo** |
| 2 | Cài đặt → Pin → Khởi chạy ứng dụng → Hermes Display | Tắt "Quản lý tự động", bật cả 3: **Tự khởi chạy**, **Khởi chạy phụ**, **Chạy nền** |
| 3 | Cài đặt → Pin (hoặc Ứng dụng → Hermes Display → Pin) | **Không tối ưu hoá pin** / tắt tiết kiệm pin cho app |
| 4 | Cài đặt → Hệ thống → Tuỳ chọn nhà phát triển* | Bật **"Không khoá màn hình khi sạc" (Stay awake)** |
| 5 | Cài đặt → Ứng dụng → Hermes Display → Quyền | Bật **"Hiển thị cửa sổ bật lên khi chạy nền"** và **"Hiển thị trên màn hình khoá"** (để "Hey Sen" bật được màn hình) |

\* Bật Tuỳ chọn nhà phát triển: Cài đặt → Giới thiệu về máy → chạm **Số bản tạo** 7 lần.

### 2.4. Kết nối Hub lần đầu
1. Chạm biểu tượng **⚙️ Cài đặt** trên thanh nhập phía dưới.
2. **Địa chỉ Hub**: IP LAN của Mac mini (ví dụ `192.168.1.10`) hoặc hostname Tailscale (ví dụ `mac-mini`). **Cổng**: `8900`.
3. Chạm **Kiểm tra kết nối** → thấy "Kết nối thành công" → **Lưu**.
4. Huy hiệu trạng thái góc màn hình chuyển sang **"Đã kết nối"**.

### 2.5. Cài model từ khoá
Lần chạy đầu app tự tải model wake word (~6 MB). Xem tại Cài đặt → **Model từ khoá**: "Đã cài" là xong. Nếu "Tải thất bại", chạm **Thử lại**. Trong lúc chưa có model, nút micro vẫn dùng được.

### 2.6. Cập nhật phiên bản
Tải APK mới từ GitHub Releases và cài đè lên bản cũ (giữ nguyên cài đặt và trí nhớ). *OTA tự động đang phát triển (KB-003).*

---

## 3. Cấu hình & Sử dụng các Tính năng

### 3.1. 🧠 Bật não Gemini 3.8 Flash
1. Trên điện thoại/máy tính, vào **Google AI Studio**: `https://aistudio.google.com/apikey`.
2. Đăng nhập Google → **Create API key** → sao chép key (bắt đầu bằng `AIza…`). Gói miễn phí đủ dùng cho gia đình.
3. Trên tablet: ⚙️ Cài đặt → **Gemini API key** → dán key (chạm "Hiện key" để kiểm tra).
4. Mục **Bộ não trả lời** → chọn **Gemini 3.8 Flash** → **Lưu**.

| Chế độ | Ai trả lời | Khi nào dùng |
|---|---|---|
| **Gemini 3.8 Flash** (mặc định) | Gemini + Google Search, thông tin thời gian thực | Nấu ăn, thời tiết, tin tức, video, đố vui, tiếng Anh |
| **Hub (Hermes Agent)** | Hermes Agent trên Mac mini | Việc cần công cụ/ngữ cảnh riêng của Hermes |

> Chưa nhập key → app tự dùng Hub và hiện "Chưa có API key — đang dùng Hub". Key chỉ lưu trên tablet.

### 3.2. 🎙️ Tương tác bằng giọng nói ("Hey Sen")
- Nói rõ **"Hey Sen"** (phát âm tiếng Anh: *hây sen*), chờ tiếng "bíp" / sóng âm hiện lên, rồi nói câu hỏi. Ngừng nói ~1 giây là app tự gửi.
- Không muốn gọi? Chạm **nút micro** hoặc **bàn phím** để gõ.
- Huy hiệu micro: **xanh** = đang chờ "Hey Sen" · **xám** = chỉ dùng nút micro · **cam** = micro không khả dụng.

**Độ nhạy micro** (⚙️ → *Độ nhạy từ khoá "Hey Sen"*):

| Mức | Hiệu quả |
|---|---|
| **80–90%** (khuyến nghị, mặc định 80%) | Bắt tốt ở khoảng cách phòng khách 2–3 m |
| > 90% | Dễ tự kích hoạt khi TV/nhạc đang mở |
| < 70% | Phải nói to, gần máy |

**Câu hỏi mẫu:**
- 🍳 Nấu ăn: *"Hey Sen, cách nấu canh chua cá lóc"* → thẻ công thức có các bước + video.
- 💡 Mẹo vặt: *"Hey Sen, cách tẩy vết cà phê trên áo trắng"*.
- 🌤️ Thời tiết: *"Hey Sen, chiều nay Hà Nội có mưa không?"*.

> **Luôn lắng nghe** (mặc định BẬT) giữ micro khi tắt màn hình, kèm một thông báo thường trực. Vuốt tắt app khỏi danh sách đa nhiệm sẽ dừng nghe.
> **Giảm sáng ban đêm** (23:00–06:00, mặc định BẬT): màn hình mờ còn 5%; "Hey Sen" hoặc chạm để sáng lại.

### 3.3. ▶️ Xem video YouTube trực tiếp
- Khi câu trả lời có video, thẻ hiện ảnh xem trước → chạm **Phát Video**: video phát **ngay trong thẻ**, không mở app YouTube, không văng khỏi màn hình.
- Chạm **⛶ Toàn màn hình** để phóng to; chạm **Thoát toàn màn hình** hoặc nút Back để quay lại.
- Nói "Hey Sen" khi đang xem: câu hỏi mới thay thế thẻ hiện tại.

### 3.4. 💾 Nút "Lưu vào Hermes"
- Dưới mỗi thẻ công thức/ghi chú có nút **💾 Lưu vào Hermes**. Chạm → "Đang lưu…" → **"Đã lưu vào Second Brain"**.
- Ghi chú được Hub ghi vào vault Obsidian trên Mac mini:
  `~/Documents/codebase/second-brain/Knowledge/<recipes|notes>/<Tiêu đề>.md`.
- Hoạt động qua **LAN nội bộ** hoặc **Tailscale** (dùng cùng địa chỉ Hub ở mục 2.4). Báo "Không lưu được" → xem mục 5.3.

### 3.5. 👨‍👩‍👧 Hàng Avatar Gia đình (Sen OS Member Switcher)
- Hàng avatar ở **giữa phía trên** màn hình: **T** (Bố Thức) · **M** (Mẹ) · **B** (Bé). Chạm để chọn người đang nói chuyện; avatar được chọn sáng lên.
- Lựa chọn được ghi nhớ sau khi tắt/mở app.
- **Cơ chế nhớ:** mỗi thành viên có trí nhớ riêng (SQLite trên tablet): sở thích, thói quen, tiến độ đố vui/tiếng Anh. Trước mỗi câu hỏi, Sen gửi kèm tóm tắt ngắn (≤ 600 ký tự) về người đang chọn, nên câu trả lời được cá nhân hoá (ví dụ Bố Thức hỏi đồ uống → Sen nhớ "cà phê ít đường").
- Đổi sang **Bé** trước khi cho con chơi: đố vui dễ hơn, tiếng Anh câu ngắn hơn.

### 3.6. 🧩 Đố vui & 🗣️ Học tiếng Anh
**Đố vui**
- Kích hoạt: *"Hey Sen, đố vui đi"* / *"câu đố"* / *"chơi game"* / *"quiz"*.
- Thẻ hiện câu hỏi + 4 đáp án A–D. Trả lời bằng **chạm** vào đáp án hoặc **nói** *"đáp án B"*.
- Đúng → thẻ xanh "Chính xác! 🎉"; sai → thẻ đỏ kèm đáp án đúng và giải thích. Nói *"câu tiếp theo"* để chơi tiếp (kỹ năng giữ nguyên qua các lượt).

**Luyện tiếng Anh nhập vai**
- Kích hoạt: *"Hey Sen, học tiếng Anh"* / *"English"* / *"roleplay"*.
- Sen đóng vai (người phục vụ quán cà phê, nhân viên sân bay…), mỗi lượt 1–2 câu tiếng Anh + bản dịch + tối đa 3 từ vựng.
- Trả lời bằng giọng nói hoặc gõ. Trình độ tự điều chỉnh theo thành viên đang chọn.

**Thoát kỹ năng:** hỏi chuyện khác bất kỳ, hoặc chạm **✕ Đóng** trên thẻ.

---

## 4. Tự tạo Kỹ năng & Tùy biến bằng Obsidian

Vault Obsidian có thư mục **`Sen/`** — "bộ não" dạng văn bản của Sen:

```
Sen/
├── Sen.md          # Trang tổng (MOC): thành viên, kỹ năng, nghi thức, nhật ký
├── members/        # Hồ sơ thành viên
├── skills/         # Kỹ năng (prompt + quy tắc)
├── rituals/        # Nghi thức gia đình
├── journal/        # Nhật ký hằng ngày
└── assets/         # avatars/, voice/
```

> ⚠️ **Trạng thái hiện tại (v0.5.0):** app trên tablet **chưa đọc trực tiếp** thư mục `Sen/`. Thành viên và kỹ năng đang được định nghĩa trong app (Bố Thức / Mẹ / Bé; Đố vui, Tiếng Anh). Các file trong `Sen/` là nguồn chuẩn để Hermes Agent tham chiếu và là đặc tả cho tính năng **hot-reload no-code** sắp tới — viết đúng mẫu ngay từ bây giờ để khi bật đồng bộ, Sen dùng được ngay không cần sửa.

### 4.1. Tạo kỹ năng mới (`Sen/skills/`)
1. Obsidian → thư mục `Sen/skills/` → tạo file mới, tên viết thường không dấu, nối bằng `-` (ví dụ `doc-tho.md`).
2. Lệnh **Templates: Insert template** → chọn **Sen Skill Template**.
3. Điền frontmatter:
   ```yaml
   type: sen/skill
   id: doc-tho
   name: Đọc thơ
   triggers: ["đọc thơ", "bài thơ"]
   members: [be]
   output: text        # text: đọc to · json: hiển thị thẻ
   status: active      # draft | active | paused
   ```
4. Viết phần **Prompt (system instruction)**: Sen làm gì, độ dài, giọng điệu, điều cấm. Dùng `{{member.name}}`, `{{member.role}}`, `{{member.english_level}}` làm chỗ điền thông tin thành viên.
5. Tham khảo mẫu: `do-vui.md`, `bedtime-story.md`, `roleplay-tieng-anh.md`.

### 4.2. Tạo hồ sơ thành viên mới (`Sen/members/`)
1. Tạo `Sen/members/<id>.md` (ví dụ `ba-noi.md`) → chèn **Sen Member Template**.
2. Điền frontmatter: `id`, `name`, `aliases`, `role` (`father|mother|child|grandparent|other`), `english_level` (`starter|beginner|intermediate|advanced`), `call_me` (Sen gọi người đó thế nào), `avatar`.
3. Đặt ảnh đại diện vuông (khuyến nghị 512×512 PNG) vào `Sen/assets/avatars/<id>.png`.
4. Viết các mục **Sở thích & Thói quen**, **Sen nên biết**, **Mục tiêu tháng này**, **Điều cấm kỵ với Sen** bằng gạch đầu dòng ngắn — mỗi dòng là một "sự thật" Sen nhớ.

### 4.3. Tạo nghi thức gia đình (`Sen/rituals/`)
1. Tạo `Sen/rituals/<id>.md` → chèn **Sen Ritual Template**.
2. Điền `schedule` (giờ `HH:MM`), `days`, `members`.
3. Viết **Kịch bản** từng bước và **Quy tắc**. Mẫu: `bua-toi-family-checkin.md` (19:30, "Điều vui nhất hôm nay là gì?"), `khen-tang-dong-vien.md` (khen gián tiếp).
4. Kết quả nghi thức ghi vào `Sen/journal/sen-YYYY-MM-DD.md`.

**Mẹo:** mở `Sen/Sen.md` để xem bảng tổng hợp tự động (cần plugin **Dataview**). File thiếu `type:` đúng sẽ không hiện trong bảng.

---

## 5. Khắc phục sự cố & FAQ

### 5.1. "Hey Sen" không kích hoạt
| Kiểm tra | Cách xử lý |
|---|---|
| Huy hiệu micro **cam** | Cài đặt hệ thống → Ứng dụng → Hermes Display → Quyền → bật **Micro** |
| Huy hiệu micro **xám** | Model chưa cài: ⚙️ → **Model từ khoá** → **Thử lại** (cần internet) |
| Model "Đã cài" nhưng không bắt | Tăng **độ nhạy** lên 85–90%; nói rõ "Hey Sen" cách máy ≤ 3 m; tắt bớt TV/nhạc |
| Từ khoá đã bị đổi | ⚙️ → **Từ khoá đánh thức** → đặt lại `HEY SEN` (chỉ chữ A–Z tiếng Anh) |
| Tắt màn hình là hết nghe | Bật **Luôn lắng nghe**; làm lại bước 2–3 ở mục 2.3; không vuốt tắt app khỏi đa nhiệm |
| Màn hình không bật khi gọi | Bật **"Hiển thị cửa sổ bật lên khi chạy nền"** + **"Hiển thị trên màn hình khoá"** (mục 2.3 bước 5) |

### 5.2. Không có tiếng đọc
- Huy hiệu **"Mất kết nối"** → TTS do Hub đọc, kiểm tra Hub đang chạy và địa chỉ Hub đúng (⚙️ → **Kiểm tra kết nối**).
- Có chữ nhưng không có tiếng → kiểm tra **âm lượng media** của tablet (không phải âm lượng chuông).
- Chế độ Gemini báo lỗi → kiểm tra **internet** và **API key** (key sai/hết hạn mức miễn phí).

### 5.3. Kết nối Mac mini: Tailscale vs LAN nội bộ
| | LAN nội bộ | Tailscale |
|---|---|---|
| Địa chỉ Hub | IP Mac mini, ví dụ `192.168.1.10` | Tên máy hoặc IP `100.x.y.z` |
| Khi nào dùng | Tablet và Mac mini cùng Wi-Fi nhà | Khác mạng, hoặc router hay đổi IP |
| Độ trễ | Thấp nhất | Thấp (kết nối trực tiếp khi có thể) |
| Cài đặt | Đặt **IP tĩnh / DHCP reservation** cho Mac mini trên router | Cài app Tailscale trên tablet + Mac mini, đăng nhập cùng tài khoản |

**Kiểm tra nhanh:** trên tablet mở trình duyệt `http://<địa-chỉ-hub>:8900` — trang có phản hồi (kể cả báo lỗi) là mạng thông. Không phản hồi:
- Mac mini đang ngủ → System Settings → Energy → tắt chế độ ngủ.
- Firewall macOS chặn → cho phép kết nối đến `hermes-voice-bridge`.
- Tailscale trên tablet bị EMUI tắt → áp dụng bước 2–3 mục 2.3 cho app Tailscale.

### 5.4. FAQ
- **App có chạy khi không có Mac mini không?** Có: slideshow, đồng hồ, gõ câu hỏi với Gemini. Giọng nói, đọc to, lưu ghi chú cần Hub.
- **Dữ liệu trí nhớ lưu ở đâu?** SQLite trên tablet. Gỡ app là mất.
- **Gemini API key có bị lộ không?** Key chỉ lưu trong bộ nhớ app trên tablet, hiển thị dạng ẩn.
- **Trẻ em dùng có an toàn không?** Chọn avatar **Bé** trước khi cho con dùng; nội dung được điều chỉnh theo hồ sơ. Không thay thế sự giám sát của bố mẹ.
