# Phát hành & OTA

## 1. Khoá ký (một lần)

OTA chỉ cài đè được khi APK mới ký **cùng khoá** với bản đang cài. Mất khoá = phải gỡ app (mất dữ liệu) để cài lại.

```bash
keytool -genkey -v -keystore ~/keys/hermes-display.jks \
  -keyalg RSA -keysize 4096 -validity 10000 -alias hermes
```

`android/key.properties` (đã gitignore):

```properties
storeFile=/Users/mac/keys/hermes-display.jks
storePassword=...
keyAlias=hermes
keyPassword=...
```

Không có file này, bản release được ký bằng debug key (chỉ dùng thử).

Bản đang cài ký debug key → lần chuyển sang khoá release phải gỡ và cài lại một lần.

## 2. Phiên bản

- `versionName` (`--build-name`): hiển thị, ví dụ `0.5.2`.
- `versionCode` (`--build-number`): số nguyên, **phải tăng** mỗi bản. Tablet chỉ cài khi `versionCode` mới > bản đang chạy.
- Dùng một nguồn `versionCode` duy nhất: hoặc CI (`github.run_number`), hoặc build tay. Trộn hai nguồn dễ phát hành số nhỏ hơn bản đã cài.

## 3. Build & đẩy lên Hub (Mac mini)

```bash
scripts/release.sh 0.5.2 5 "Sửa lỗi micro"
```

Script build `flutter build apk --release --build-name 0.5.2 --build-number 5`, rồi gọi `~/hermes-voice-bridge/tools/publish_apk.py`: chép APK vào `releases/` và ghi `releases/latest.json`. `display_hub.py` phát ngay, không cần khởi động lại:

- `GET /api/app/latest` → `{"versionCode":5,"versionName":"0.5.2","url":".../api/app/apk/hermes-display-5.apk","sha256":"...","notes":"..."}`
- `GET /api/app/apk/hermes-display-5.apk` → file APK

Biến môi trường: `HUB_DIR` (thư mục hermes-voice-bridge), `PUBLISH=0` (chỉ build). Thư mục release của Hub: `DISPLAY_HUB_APK_DIR`.

Bản phát hành ngoài Hub (GitHub Releases, S3…): ghi `latest.json` có sẵn `url` + `sha256` tuyệt đối, Hub trả nguyên văn; hoặc host JSON đó ở bất kỳ đâu và dán URL vào Cài đặt → **URL cập nhật ứng dụng**.

## 4. CI (GitHub Actions)

Tag `v0.5.2` → `.github/workflows/android-build.yml` build với `--build-name 0.5.2 --build-number <run_number>` và đính APK vào GitHub Release.

Secrets để ký release (không có thì ký debug):

| Secret | Giá trị |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -i ~/keys/hermes-display.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | storePassword |
| `ANDROID_KEY_ALIAS` | keyAlias |
| `ANDROID_KEY_PASSWORD` | keyPassword |

## 5. Trên tablet

1. Kiểm tra khi mở app và mỗi đêm trong khung giảm sáng (kể cả khi tắt giảm sáng).
2. Tải vào cache, kiểm SHA-256, hiện nhãn "Đã có bản cập nhật vX — Chạm để cài đặt".
3. Chạm → trình cài đặt hệ thống (lần đầu: bật "Cài ứng dụng không rõ nguồn").
4. `MY_PACKAGE_REPLACED` → `UpdateReceiver` mở lại app. Android 10+ chỉ cho phép khi app là Home mặc định hoặc có quyền "Hiển thị trên ứng dụng khác"; nếu không, mở app bằng tay.
