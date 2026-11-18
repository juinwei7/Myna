# Spec 001 — 驗收標準

執行方式：

```bash
# 在專案根目錄
.venv/bin/python -m unittest discover -s studio/tests -t .          # 快速（假引擎）
VOICE_STUDIO_SLOW=1 .venv/bin/python -m unittest studio.tests.test_slow_models  # 真模型
```

---

## A — 目錄與能力（憲法 A2）

| # | 檢查 | 通過條件 |
|---|---|---|
| A1 | 目錄完整 | 8 個模型，代號不重複，每個家族都有轉接器 |
| A2 | 能力一致 | 有配音員的模型才宣告配音員方式；語氣方式是已宣告方式的子集 |
| A3 | 授權標示 | 每個模型都有授權字串；Breeze 標為不可商用 |
| A4 | 自訂模型 | Qwen3 配音員版的設定推導出配音員方式與名單；不支援的家族回錯誤 |

## B — 請求解析與相容（約束 C-1）

| # | 檢查 | 通過條件 |
|---|---|---|
| B1 | 舊代號 `clone:tw-female` | 仿聲、模型 `qwen3-1.7b-base` |
| B2 | 舊代號 `preset:Vivian` | 配音員、模型 `qwen3-1.7b-custom` |
| B3 | 舊代號 `design` | 聲音描述、模型 `qwen3-1.7b-design`；沒描述時報錯 |
| B4 | 指定模型 | `mode=clone, model=voxcpm2` 用 VoxCPM2 |
| B5 | 方式不支援 | `mode=preset, model=voxcpm2` 回「不支援」錯誤 |
| B6 | 未下載 | 回「還沒下載」錯誤 |
| B7 | 批次全有或全無 | 其中一個模型不合格時，一筆都不排 |
| B8 | 語氣指令 | 不支援語氣的方式不把 `instruct` 傳給模型 |

## C — 轉接器

| # | 檢查 | 通過條件 |
|---|---|---|
| C1 | Qwen3 仿聲 | 傳 `ref_audio`、`ref_text`、`lang_code=chinese` |
| C2 | Qwen3 配音員 | 傳 `voice`，有語氣時傳 `instruct` |
| C3 | Breeze 仿聲＋語氣 | 傳 `instruct` 與 `cfg_scale` |
| C4 | OmniVoice 語速 | 語速 1.25 時 `duration_s` ≈ 自然長度 ÷ 1.25；且不再跑 ffmpeg |
| C5 | MOSS Nano | 傳 `ref_audio` |

## D — 產生流程

| # | 檢查 | 通過條件 |
|---|---|---|
| D1 | 分段 | 空行、換行、長句各自正確切開；停頓長度依類型 |
| D2 | 發音字典 | 「山嵐」送進模型前變成「山藍」，紀錄保留原文與實際唸的文字 |
| D3 | 進度 | 五段稿子的進度依段數遞增，結束時為 1 |
| D4 | 取消排隊中 | 狀態變 cancelled，不產生檔案 |
| D5 | 取消產生中 | 在段與段之間停下，狀態 cancelled，不留下檔案與紀錄 |
| D6 | 紀錄欄位 | 含 `model`、`model_name`、`mode`、`spoken` |
| D7 | 舊紀錄 | 沒有 `model` 欄位的舊紀錄仍讀得出來，並推得模型名稱 |

## E — 模型生命週期

| # | 檢查 | 通過條件 |
|---|---|---|
| E1 | 已下載判斷 | 快照齊全才算；有 `.incomplete` 不算；附屬模型缺一不算 |
| E2 | 下載進度 | 假下載過程中進度介於 0～1 且遞增，完成後狀態 downloaded |
| E3 | 取消下載 | 子程序結束，狀態回 available |
| E4 | 刪除 | 只刪該模型資料夾；共用的附屬模型保留 |
| E5 | 記憶體上限 | 上限只夠兩個時，載入第三個會卸載最久沒用的 |
| E6 | 不卸載使用中的 | 單一模型超過上限仍可載入 |

## F — API 與 MCP（約束 C-3、憲法 A6）

| # | 檢查 | 通過條件 |
|---|---|---|
| F1 | `/api/models` | 回傳 8 個模型與狀態欄位 |
| F2 | 送出並取得結果 | `POST /api/jobs` → 輪詢 → done，音檔可從 `/audio/` 下載 |
| F3 | 批次 | 送兩個模型得到兩筆同 `batch` 的工作 |
| F4 | 存成聲音 | 成品存成聲音後，聲音庫多一筆，逐字稿是實際唸的文字 |
| F5 | 刪除與還原 | 刪除紀錄後還原，清單恢復 |
| F6 | 路徑檢查 | `/audio/../x`、還原資料夾外的路徑都被拒絕 |
| F7 | MCP 工具 | `tools/list` 含 `list_models`、`synthesize`；舊參數呼叫成功 |
| F8 | MCP 等待上限 | `synthesize` 在 15 秒內回應（做不完回 `job_id`） |

## G — 真模型（慢速）

| # | 檢查 | 通過條件 |
|---|---|---|
| G1 | 每個已下載的目錄模型 | 產生測試句，Breeze ASR 錯字率 ≤ 15% |
