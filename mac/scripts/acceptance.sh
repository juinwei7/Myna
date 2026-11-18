#!/usr/bin/env bash
# 九官鳥的打包與生命週期驗收（Spec 002 驗收 B、C）。
#
# 每一條都實際起 app、實際查服務、實際數殘留程序。用獨立的連接埠與暫存資料夾，
# 不會碰到正式使用中的九官鳥。跑法：make test（要先 make app）
set -uo pipefail
cd "$(dirname "$0")/.."

APP="build/九官鳥.app"
PORT=8795
DATA="$(mktemp -d /tmp/voicestudio_acc.XXXXXX)"
PASS=0; FAIL=0

say()  { printf "\n\033[1m%s\033[0m\n" "$*"; }
ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; PASS=$((PASS+1)); }
bad()  { printf "  \033[31m✗\033[0m %s\n" "$*"; FAIL=$((FAIL+1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist" 2>/dev/null; }
# 只算這次驗收起的後端（靠連接埠辨識），不會誤算正式的那一份
backend_pid() { lsof -nP -iTCP:$PORT -sTCP:LISTEN -t 2>/dev/null | head -1; }
health() { curl -s -m 2 "http://127.0.0.1:$PORT/api/health" 2>/dev/null; }

[ -d "$APP" ] || { echo "找不到 $APP，先跑 make app"; exit 1; }
[ -z "$(backend_pid)" ] || { echo "連接埠 $PORT 已經有人在用"; exit 1; }

say "B — 打包"
check "B1 簽章驗證通過" 'codesign --verify --deep --strict "$APP" 2>/dev/null'
BK="$APP/Contents/Resources/backend"
check "B2 內附後端可以匯入" '(cd "$BK" && VOICE_STUDIO_HOME="$DATA/import" bin/python3 -c "import studio.app" 2>/dev/null)'
check "B2 不含測試檔" '[ ! -e "$BK/studio/tests" ]'
check "B3 名稱是九官鳥" '[ "$(plist CFBundleName)" = "九官鳥" ]'
check "B3 有圖示檔" '[ -s "$APP/Contents/Resources/$(plist CFBundleIconFile).icns" ]'
check "B4 宣告了服務選單" '[ "$(plist NSServices:0:NSMessage)" = "speakText" ]'

say "C — 生命週期"
# 直接跑 bundle 裡的執行檔，才拿得到它的 PID；用 open 的話拿不到
VOICE_STUDIO_HOME="$DATA/home" "$APP/Contents/MacOS/VoiceStudio" -servicePort $PORT >"$DATA/app.log" 2>&1 &
APP_PID=$!
for _ in $(seq 1 120); do [ -n "$(health)" ] && break; sleep 0.5; done
check "C1 60 秒內服務就緒" '[ -n "$(health)" ]'
check "C1 服務用的是暫存資料夾" 'health | grep -q "$DATA/home"'
COUNT=$(curl -s -m 5 "http://127.0.0.1:$PORT/api/models" | /usr/bin/python3 -c "import sys,json; print(len(json.load(sys.stdin)['models']))" 2>/dev/null)
check "C2 模型清單有 8 個" '[ "$COUNT" = "8" ]'
check "C2 沒有網頁介面（根路徑 404）" '[ "$(curl -s -m 3 -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT/")" = "404" ]'
MCP_TOOLS=$(curl -s -m 5 -X POST "http://127.0.0.1:$PORT/mcp" -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' \
    | /usr/bin/python3 -c "import sys,json; print(' '.join(sorted(t['name'] for t in json.load(sys.stdin)['result']['tools'])))" 2>/dev/null)
check "C2 MCP 有回應且含 synthesize、list_models" 'echo "$MCP_TOOLS" | grep -q synthesize && echo "$MCP_TOOLS" | grep -q list_models'
check "C2 MCP 有 speak（Spec 003）" 'echo "$MCP_TOOLS" | grep -qw speak'
check "C2 設定有 allow_speak（Spec 003）" 'curl -s -m 3 "http://127.0.0.1:$PORT/api/settings" | grep -q "\"allow_speak\":true"'
BACKEND_PID="$(backend_pid)"
check "C2 後端是 app 內附的那一份" 'ps -p "$BACKEND_PID" -o command= | grep -q "$PWD/$APP/Contents/Resources/backend"'

# C4：連接埠上已有服務時，第二個 app 不另開一份
VOICE_STUDIO_HOME="$DATA/home2" "$APP/Contents/MacOS/VoiceStudio" -servicePort $PORT >"$DATA/app2.log" 2>&1 &
SECOND_PID=$!
sleep 4
check "C4 沿用既有的服務" '[ "$(backend_pid)" = "$BACKEND_PID" ] && [ "$(lsof -nP -iTCP:$PORT -sTCP:LISTEN -t | wc -l | tr -d " ")" = "1" ]'
kill "$SECOND_PID" 2>/dev/null; wait "$SECOND_PID" 2>/dev/null
check "C4 第二個 app 結束不影響服務" '[ -n "$(health)" ]'

# C3：結束 app（SIGTERM 會走正常結束流程）後，後端不殘留
kill "$APP_PID" 2>/dev/null
for _ in $(seq 1 20); do kill -0 "$APP_PID" 2>/dev/null || break; sleep 0.5; done
sleep 1
check "C3 app 已結束" '! kill -0 "$APP_PID" 2>/dev/null'
check "C3 後端沒有殘留" '! kill -0 "$BACKEND_PID" 2>/dev/null && [ -z "$(backend_pid)" ]'

# C5：app 被強制結束（沒機會收尾）時，後端自己發現並收工
VOICE_STUDIO_HOME="$DATA/home" "$APP/Contents/MacOS/VoiceStudio" -servicePort $PORT >"$DATA/app3.log" 2>&1 &
APP_PID=$!
for _ in $(seq 1 120); do [ -n "$(health)" ] && break; sleep 0.5; done
BACKEND_PID="$(backend_pid)"
kill -9 "$APP_PID" 2>/dev/null
for _ in $(seq 1 20); do kill -0 "$BACKEND_PID" 2>/dev/null || break; sleep 0.5; done
check "C5 app 被強制結束後，後端 10 秒內自己結束" '[ -n "$BACKEND_PID" ] && ! kill -0 "$BACKEND_PID" 2>/dev/null'

# 萬一上面失敗，別把程序留在機器上
kill "$APP_PID" "$BACKEND_PID" 2>/dev/null
rm -rf "$DATA"
defaults delete local.weiwei.voicestudio.test >/dev/null 2>&1

printf "\n通過 %d，失敗 %d\n" "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
