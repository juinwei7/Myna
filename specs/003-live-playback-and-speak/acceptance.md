# Spec 003 — 驗收標準

執行方式：

```bash
.venv/bin/python -m unittest discover -s studio/tests -t .     # A、B（假引擎）
cd mac && swift test                                             # C1～C3
node --test site/src/pages.test.mjs                              # C4、D2
node site/build.mjs                                              # D1（缺音檔會失敗）
cd mac && make app && ./scripts/acceptance.sh                    # 打包後的 app 有 speak、allow_speak

# 真的服務＋真的模型（連接埠挑沒人用的）
VOICE_STUDIO_HOME=/tmp/myna-demo VOICE_STUDIO_PORT=8791 .venv/bin/python -m studio.app &
cd mac && VOICE_STUDIO_TEST_PORT=8791 VOICE_STUDIO_HOME=/tmp/myna-demo swift test    # C5～C8（靜音播放）
VOICE_STUDIO_ASR_PYTHON=<裝了 mlx_whisper 的 python> VOICE_STUDIO_ASR_MODEL=<Whisper 模型> \
  python3 site/make-samples.py --check                                               # D4
```

結果（2026-11-18）：後端 68 個測試通過（2 個慢速的略過）；app 27 個通過，其中 12 個對著真的服務跑；
官網 4 個通過；打包驗收 19 條通過；8 段試聽的錯字率都是 0%。

---

## A — 分段成品

| # | 檢查 | 通過條件 |
|---|---|---|
| A1 | 多段的稿子 | 三段的稿子產生過程中，`parts` 從 0 遞增到 3，每個檔都是讀得出來的 wav |
| A2 | 分段接起來等於成品 | 各段的取樣數加起來等於成品的取樣數 |
| A3 | 只有一段 | 不寫分段成品，`parts` 維持 0 |
| A4 | 語速 | 調語速時每一段都已經是調過的；缺 ffmpeg 時在產生前就報錯，模型一次都沒被呼叫 |
| A5 | 取消 | 產生途中取消，這個工作的分段資料夾被刪掉 |
| A6 | 清理 | 結束超過一小時的分段資料夾在下一個工作開始時被刪；服務啟動時 `parts/` 是空的 |
| A7 | 欄位 | 工作的檢視有 `speak`、`segments`、`parts`、`parts_dir`；舊欄位都還在 |

## B — 直接唸出來

| # | 檢查 | 通過條件 |
|---|---|---|
| B1 | `POST /api/speak` | 回傳的工作 `speak` 為 true，做完後出現在紀錄裡 |
| B2 | 驗證 | 文字是空的、模型不支援時回 400，跟 `/api/jobs` 一樣 |
| B3 | 開關 | `allow_speak` 設成 false 之後，`/api/speak` 回 400 並說明原因；`/api/jobs` 不受影響 |
| B4 | MCP | `tools/list` 有 `speak`；呼叫後立刻回傳 `job_id`，不等做完 |
| B5 | 相容 | `synthesize` 的工作 `speak` 為 false；既有的 MCP 工具與參數不變 |
| B6 | 設定 | `GET /api/settings` 有 `allow_speak`，預設 true；亂填的值被拒絕 |

## C — app

| # | 檢查 | 通過條件 |
|---|---|---|
| C1 | 解析 | 帶新欄位、不帶新欄位的工作 JSON 都解得出來；分段的路徑照後端給的資料夾組出來 |
| C2 | 邊做邊播的決定 | 一段播完：有下一段 → 播下一段；沒有且還在產生 → 等；已經做完 → 換成完整音檔，位置是已播各段長度的總和 |
| C3 | AI 工具的佇列 | 播放器閒著才取下一筆；失敗、取消的跳過；app 打開前就存在的不播 |
| C4 | 文案跟著版本走 | （官網）標了 `since` 的段落，最新版比它舊時不出現 |
| C5 | 真的邊做邊播 | 送一份三段的稿子，工作還在產生時播放器已經在播；做完後播放列是完整的音檔 |
| C6 | 取消 | 邊做邊播時取消工作，播放停止，播放列清掉 |
| C7 | AI 工具連說兩句 | 連續兩個 `speak`，兩句都播過，第二句沒有打斷第一句 |
| C8 | 開關關著 | `allow_speak` 關掉時 `speak` 失敗，app 沒有開始播 |
| C9 | 截圖 | 邊做邊播的播放列（淺色、深色）：左邊是播了幾秒，中間的進度條深色是播過的、淺色是做好的，右邊是「第 3／8 段」；設定的 AI 工具頁有「讓 AI 工具直接唸出來」的開關 |

## D — 官網試聽

| # | 檢查 | 通過條件 |
|---|---|---|
| D1 | 音檔齊全 | `SAMPLES` 的 8 筆在 `site/public/audio/` 都有檔案，建置才會過 |
| D2 | 頁面 | 首頁有 8 個 `<audio>`，都是 `preload="none"`，順序跟模型的表一樣；整個網站仍然沒有 `<script src>` |
| D3 | 大小 | 每個音檔小於 300 KB |
| D4 | 聽得懂 | 每個音檔用語音辨識轉回文字，錯字率 ≤ 15% |
| D5 | 線上 | 部署後 `https://myna.weibuilds.com/audio/<代號>.m4a` 回 200，型別是音訊 |
