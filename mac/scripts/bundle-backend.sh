#!/usr/bin/env bash
# 把 Python runtime、依賴、語音服務原始碼包進 .app，使用者不用另外裝 Python。
#
# 產出：<app>/Contents/Resources/backend/
#   bin/python3   內附直譯器（python-build-standalone，可重新定位）
#   lib/          標準庫＋依賴（版本照 requirements.lock，跟開發用的 .venv 同一組）
#   studio/       語音服務（Python 套件，用 python3 -m studio.app 啟動）
#
# 模型不包進來（三個加起來 12 GB），第一次用到時下載到 ~/.cache/huggingface。
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:?用法：scripts/bundle-backend.sh <app 路徑>}"
STUDIO="$(cd ../studio && pwd)"
CACHE="$HOME/Library/Caches/voicestudio-runtime"
PY_VERSION="3.11.16"
PBS_RELEASE="20260901"
RUNTIME_ARCH="aarch64-apple-darwin"   # MLX 只支援 Apple Silicon

say() { printf "\033[1m→ %s\033[0m\n" "$*"; }
die() { printf "\033[31m✗ %s\033[0m\n" "$*" >&2; exit 1; }

[ -d "$APP" ] || die "找不到 $APP"
[ "$(uname -m)" = arm64 ] || die "MLX 只能在 Apple Silicon 上跑"

mkdir -p "$CACHE"
TARBALL="$CACHE/cpython-$PY_VERSION-$PBS_RELEASE-$RUNTIME_ARCH.tar.gz"
if [ ! -f "$TARBALL" ]; then
    ASSET="cpython-${PY_VERSION}%2B${PBS_RELEASE}-${RUNTIME_ARCH}-install_only_stripped.tar.gz"
    URL="https://github.com/astral-sh/python-build-standalone/releases/download/${PBS_RELEASE}/${ASSET}"
    say "下載 Python runtime（${PY_VERSION} / ${PBS_RELEASE}）"
    curl -sSfL --max-time 300 "$URL" -o "$TARBALL.tmp" || die "下載失敗：$URL"
    mv "$TARBALL.tmp" "$TARBALL"
else
    say "使用已快取的 runtime"
fi

# runtime＋依賴先組在暫存區，requirements.lock 沒變就沿用（裝一次要好幾分鐘）
BACKEND="$PWD/.build/backend-stage"
STAMP="$PY_VERSION-$PBS_RELEASE-$(shasum -a 256 requirements.lock | cut -c1-16)"
if [ "$(cat "$BACKEND/.stamp" 2>/dev/null)" != "$STAMP" ]; then
    rm -rf "$BACKEND"
    mkdir -p "$BACKEND"
    say "解開 runtime"
    tar -xzf "$TARBALL" -C "$BACKEND" --strip-components 1
    PY="$BACKEND/bin/python3"
    [ -x "$PY" ] || die "解開後找不到 $PY"
    say "安裝依賴（約 650 MB，第一次比較久）"
    "$PY" -m pip install --quiet --upgrade pip >/dev/null 2>&1 || true
    "$PY" -m pip install --quiet --no-warn-script-location -r requirements.lock || die "依賴安裝失敗"
    PRUNE=1
else
    say "沿用已安裝的依賴"
    PRUNE=0
fi
PY="$BACKEND/bin/python3"

say "複製語音服務原始碼"
# studio 是套件，整包複製；測試不用帶進 app
rm -rf "$BACKEND/studio"
rsync -a --exclude tests --exclude __pycache__ "$STUDIO/" "$BACKEND/studio/"

if [ "$PRUNE" = 1 ]; then
say "精簡"
LIBDIR="$BACKEND/lib/python${PY_VERSION%.*}"
rm -f "$BACKEND/lib/libpython"*.dylib "$BACKEND/lib/libpython"*.a
rm -rf "$LIBDIR/ensurepip" "$LIBDIR/site-packages/pip" "$LIBDIR/site-packages"/pip-*.dist-info
rm -f "$BACKEND/bin/pip" "$BACKEND/bin/pip3" "$BACKEND/bin"/pip3.*
rm -rf "$BACKEND/lib/tcl"* "$BACKEND/lib/tk"* "$LIBDIR/tkinter" "$LIBDIR/turtledemo" "$LIBDIR/idlelib"
rm -f "$BACKEND/lib/libtcl"*.dylib "$BACKEND/lib/libtk"*.dylib "$LIBDIR/lib-dynload/_tkinter"*.so
rm -rf "$BACKEND/include" "$BACKEND/share" "$LIBDIR/config-"* "$LIBDIR/lib2to3" "$LIBDIR/pydoc_data"
find "$BACKEND" -type d \( -name test -o -name tests \) -prune -exec rm -rf {} + 2>/dev/null || true
fi

# 整包先編成 .pyc：執行時才產生會寫進已簽章的 bundle，破壞封印
say "預先編譯 .pyc"
"$PY" -m compileall -q -j 0 "$BACKEND/lib" "$BACKEND/studio" >/dev/null 2>&1 || true

say "匯入驗證"
"$PY" -I -c "import mlx.core, mlx_audio.tts.utils, fastapi, uvicorn, mcp.server.mcpserver; print('  依賴 OK')" \
    || die "內附的依賴不完整"
# 匯入時會建立資料夾，指到暫存位置，不要碰到正式資料
(cd "$BACKEND" && VOICE_STUDIO_HOME="$(mktemp -d)" "$PY" -c "import studio.app; print('  語音服務 OK')") \
    || die "語音服務匯入失敗"

echo "$STAMP" > "$BACKEND/.stamp"

say "放進 app"
rm -rf "$APP/Contents/Resources/backend"
ditto "$BACKEND" "$APP/Contents/Resources/backend"
rm -f "$APP/Contents/Resources/backend/.stamp"
du -sh "$APP/Contents/Resources/backend" | awk '{print "  backend 大小：" $1}'
