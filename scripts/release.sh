#!/usr/bin/env bash
# Build a signed release APK and (optionally) publish it to the hub for OTA.
#
#   scripts/release.sh <versionName> <versionCode> [notes]
#   e.g. scripts/release.sh 0.5.2 5 "Sửa lỗi micro"
#
# Signing: android/key.properties (see docs/RELEASE.md); without it the APK
# is debug-signed and cannot update a release-signed install.
# Publish: set HUB_DIR (default ~/hermes-voice-bridge) to copy the APK
# into the hub's releases/ via tools/publish_apk.py; PUBLISH=0 skips it.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ $# -lt 2 ]; then
  sed -n '2,11p' "$0"
  exit 64
fi
NAME="$1"
CODE="$2"
NOTES="${3:-}"
HUB_DIR="${HUB_DIR:-$HOME/hermes-voice-bridge}"
APK=build/app/outputs/flutter-apk/app-release.apk

if [ ! -f android/key.properties ]; then
  echo "!! android/key.properties missing: APK will be debug-signed" >&2
fi

flutter build apk --release --build-name="$NAME" --build-number="$CODE"
shasum -a 256 "$APK"

if [ "${PUBLISH:-1}" = "0" ]; then
  exit 0
fi
python3 "$HUB_DIR/tools/publish_apk.py" "$APK" \
  --version-code "$CODE" --version-name "$NAME" --notes "$NOTES"
