# Spec 001 — 任務拆解

- [x] T1 — 拆成 `studio` 套件，`python -m studio.app` 啟動；`config.py` 集中路徑與環境變數
- [x] T2 — `catalog.py`：8 個模型、能力欄位、預設模型、自訂模型推導
- [x] T3 — `adapters.py`：qwen3_tts、breeze_tts、voxcpm2、omnivoice、moss_tts_nano 五個家族
- [x] T4 — `text.py`：發音字典、分段、停頓、語言判斷
- [x] T5 — `resolve.py`：統一請求、舊聲音代號、驗證、批次
- [x] T6 — `models.py`：已下載判斷、子程序下載、進度、取消、刪除、附屬模型
- [x] T7 — `engine.py`：載入／卸載與記憶體上限、分段產生、靜音拼接、語速、參考音訊快取
- [x] T8 — `jobs.py`：單一執行緒佇列、進度、取消（排隊中／產生中）、批次、載入工作
- [x] T9 — `voices.py`、`history.py`、`settings.py`：修改、刪除、還原、存成聲音
- [x] T10 — `app.py`：REST 端點、MCP 工具擴充
- [x] T11 — 網頁版跟上：方式＋模型選擇（網頁版已於 2026-11-18 整個拿掉，只留 REST 與 MCP）
- [x] T12 — 假引擎、假下載程式、單元測試、API 測試
- [x] T13 — 慢速測試：真模型＋ASR 錯字率
- [x] T14 — `bundle-backend.sh` 改為複製整個 `studio` 套件；supervisor 改用 `-m studio.app`

## 實作期間的發現

- **huggingface_hub 2.x 把大檔案放進整個快取共用的 `blobs/`**：刪模型要走它的清理流程（`scan_cache_dir().delete_revisions()`），
  直接刪資料夾會留下孤兒檔案。下載中的檔案仍在各模型自己的 `blobs/*.incomplete`，可以拿來算進度。
- **「下載完整」要跟 mlx-audio 抓的檔案一致**：它只抓 `*.json`、`*.safetensors` 等樣式，README 這類檔案本來就不會有；
  附屬模型（MOSS 的音訊編碼器）連 `*.py` 都沒抓，所以程式碼檔不列為必要。
- **MCP 工具回傳型別要寫 `dict[str, Any]`** 才會有結構化輸出；只寫 `dict` 的話 `structuredContent` 是空的。
- **下載進度會短暫倒退**：檔案從暫存搬進共用庫的瞬間量起來變少，所以回報的進度只增不減。
- **OmniVoice 8-bit 版載不起來**（權重對不上），目錄用 bf16 版。
