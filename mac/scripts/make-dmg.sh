#!/usr/bin/env bash
# 把 .app 包成 DMG（裡面有 app 和「應用程式」的捷徑，拖過去就裝好）。
# 用法：scripts/make-dmg.sh build/九官鳥.app   → dist/Myna-<版本>.dmg
#
# 沒有 Apple 開發者帳號，app 是 ad-hoc 簽章：使用者第一次打開要到「隱私權與安全性」按「強制打開」。
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:?用法：scripts/make-dmg.sh <app 路徑>}"
[ -d "$APP" ] || { echo "找不到 ${APP}，先跑 make app" >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
OUT="dist/Myna-${VERSION}.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

ditto "$APP" "$STAGE/$(basename "$APP")"
ln -s /Applications "$STAGE/Applications"
mkdir -p dist
rm -f "$OUT"
hdiutil create -quiet -volname "九官鳥" -srcfolder "$STAGE" -ov -format UDZO "$OUT"
echo "已產生 ${OUT}（$(du -h "$OUT" | cut -f1)）"
shasum -a 256 "$OUT"
