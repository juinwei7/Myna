#!/bin/bash
# 官網用的圖（docs/website.md §5），只能在 macOS 上跑（用系統的 sips 和 Chrome）。
# 截圖（docs/images）或圖示換過之後跑一次，連同 site/public 一起提交。
#   - 截圖轉成 AVIF：原寬、960 寬，品質 60
#   - favicon、apple-touch-icon
#   - 分享預覽圖 og.png（1200×630，用 site/og.html 截圖；沒有 Chrome 就跳過）
set -euo pipefail
cd "$(dirname "$0")/.."
out=site/public
shots=(studio voices versions models)

# 長寬要是偶數（960 寬的版本也是）：sips 轉奇數尺寸的圖會產生壞掉的 AVIF，Chrome 看得到，Safari、Firefox 一片空白
for name in "${shots[@]}"; do
  w=$(sips -g pixelWidth "docs/images/$name.png" | awk '/pixelWidth/ {print $2}')
  h=$(sips -g pixelHeight "docs/images/$name.png" | awk '/pixelHeight/ {print $2}')
  small=$(( (h * 960 + w / 2) / w ))
  if (( w % 2 || h % 2 || small % 2 )); then
    echo "docs/images/$name.png 是 ${w}×${h}（960 寬時高 ${small}）：長寬要是偶數，請先裁切" >&2
    exit 1
  fi
done
mkdir -p "$out/images"
for name in "${shots[@]}"; do
  sips -s format avif -s formatOptions 60 "docs/images/$name.png" --out "$out/images/$name.avif" >/dev/null
  sips -s format avif -s formatOptions 60 --resampleWidth 960 "docs/images/$name.png" --out "$out/images/$name-960.avif" >/dev/null
done

sips -z 64 64 docs/images/icon.png --out "$out/favicon.png" >/dev/null
sips -z 180 180 docs/images/icon.png --out "$out/apple-touch-icon.png" >/dev/null

chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if [ -x "$chrome" ]; then
  profile="$(mktemp -d)"
  "$chrome" --headless=new --disable-gpu --hide-scrollbars --user-data-dir="$profile" \
    --force-device-scale-factor=1 --window-size=1200,630 --virtual-time-budget=3000 \
    --screenshot="$PWD/$out/og.png" "file://$PWD/site/og.html" 2>/dev/null
  rm -rf "$profile"
else
  echo "找不到 Google Chrome，沒有更新分享預覽圖"
fi
ls -la "$out" "$out/images" | awk '{print $5, $9}'
