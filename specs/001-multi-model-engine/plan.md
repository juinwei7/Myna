# Spec 001 — 技術方案

對應規格：[`spec.md`](./spec.md) · 驗收：[`acceptance.md`](./acceptance.md)

---

## 1. 模型目錄（實測結果）

2026-11-18 用同一句「歡迎使用語音工作室，今天我們來介紹幾個新的語音模型。」測試，
仿聲參考聲音是台灣女聲（`voices/tw-female`），產出交給本機 Breeze ASR 25 轉回文字算錯字率。

| 代號 | 模型 | 方式 | 大小 | 授權 | 錯字率 | 備註 |
|---|---|---|---|---|---|---|
| `qwen3-1.7b-base` | Qwen3-TTS 1.7B 仿聲 | 仿聲 | 4.5 GB | Apache-2.0 | 0% | 預設仿聲模型（相容舊行為） |
| `qwen3-1.7b-custom` | Qwen3-TTS 1.7B 配音員 | 配音員＋語氣 | 4.5 GB | Apache-2.0 | — | 9 位內建配音員，口音偏中國大陸 |
| `qwen3-1.7b-design` | Qwen3-TTS 1.7B 聲音描述 | 描述 | 4.5 GB | Apache-2.0 | — | |
| `qwen3-0.6b-base` | Qwen3-TTS 0.6B 仿聲（輕量） | 仿聲 | 2.0 GB | Apache-2.0 | 0% | 8-bit，載入快 |
| `breeze-tts-2` | Breeze-TTS 2 | 仿聲＋語氣、描述 | 4.6 GB | 研究與非商業 | 0% | 不能商用 |
| `voxcpm2` | VoxCPM2 | 仿聲、描述 | 3.2 GB | Apache-2.0 | 0% | 48 kHz，逐字稿可省略 |
| `omnivoice` | OmniVoice | 仿聲、描述 | 1.6 GB | Apache-2.0 | 0% | 最快；可指定長度＝原生語速 |
| `moss-tts-nano` | MOSS-TTS Nano | 仿聲 | 0.4 GB | Apache-2.0 | 8% | 最小；另需音訊編碼器 |

**淘汰**：Chatterbox 多語版中文錯字率 50%；OmniVoice 8-bit 版權重載不起來（改用 bf16）；
Kokoro、Spark-TTS 需要額外套件（憲法 A5）。

## 2. 模組切分

原本 470 行的 `app.py` 拆成 `studio` 套件，用 `python -m studio.app` 啟動。
**為什麼改成套件**：拆出 `config`、`history` 這種通用名稱的模組後，若仍以腳本執行，
腳本所在資料夾排在 `sys.path` 最前面，可能蓋掉第三方套件的同名模組。

| 模組 | 職責 |
|---|---|
| `config.py` | 路徑、連接埠、上限；環境變數覆寫 |
| `catalog.py` | 模型目錄（資料）、自訂模型推導 |
| `adapters.py` | 各模型家族：把統一的請求轉成該家族 `generate()` 的參數 |
| `text.py` | 發音字典、分段、語言判斷、停頓長度 |
| `voices.py` | 聲音庫：新增、修改、刪除、從成品存成聲音 |
| `history.py` | 產生紀錄：讀、寫、刪、還原 |
| `settings.py` | 預設模型、記憶體上限、自訂模型清單（`settings.json`） |
| `models.py` | 模型檔案：是否已下載、下載（子程序）、進度、取消、刪除 |
| `engine.py` | 載入／卸載（記憶體上限）、產生流程 |
| `jobs.py` | 單一執行緒佇列：產生、載入；進度、取消、批次 |
| `resolve.py` | 請求解析與驗證（含舊聲音代號） |
| `app.py` | REST、MCP |

## 3. 請求解析（`resolve.py`）

統一的請求：

```json
{"text": "...", "mode": "clone|preset|design", "voice": "tw-female 或 clone:tw-female",
 "speaker": "Vivian", "model": "voxcpm2", "instruct": "...", "speed": 1.0}
```

- **方式**：有 `mode` 用 `mode`；否則看 `voice` 的前綴（`clone:`／`preset:`／`design`）；都沒有就是仿聲。
- **模型**：有 `model` 用指定的；否則用設定裡該方式的預設模型。
  配音員沒指定模型時，找第一個「已下載、且有這位配音員」的模型（預設模型優先）。
- **驗證**（全部錯誤訊息用中文，直接顯示給使用者）：
  模型存在 → 支援這個方式 → 已下載 → 聲音／配音員存在 → 描述方式要有描述 → 文字非空且不超過上限。
- **語氣指令**：只有目錄宣告 `instruct_modes` 包含該方式時才傳給模型，否則忽略
  （舊行為就是仿聲時忽略 `instruct`，保持相容）。
- **批次**：`models: [...]` 會先把每個模型都驗證過，全部合格才一起排進佇列，避免只排了一半。

## 4. 產生流程（`engine.py`）

```
套發音字典 → 分段 → 載入模型（必要時卸載最久沒用的）
→ 每段：轉接器組參數 → generate → 收集音訊 → 更新進度、檢查取消
→ 段與段之間補靜音 → 寫 wav → 語速（原生或 ffmpeg）→ 寫紀錄
```

- **分段**（`text.py`）：空行分段落、換行分句組；單行超過 80 字再依「。！？；」切，
  還是太長就依「，」切。每段短，所有模型的最大長度限制都不會碰到，進度也才有意義。
- **停頓**：句與句 0.12 秒、行與行 0.3 秒、段落 0.6 秒。
- **語言**：文字有中日韓字元就當中文，否則英文；轉接器各自對應到該家族的參數。
- **參考音訊快取**：同一個聲音檔依（路徑、取樣率、修改時間）快取，多段稿子不用每段重讀。
- **語速**：目錄宣告 `native_speed` 的模型（OmniVoice）把語速換成目標長度交給模型；
  其他模型照舊用 ffmpeg `atempo`。

## 5. 記憶體上限

載入的模型放在依使用順序排列的字典裡。載入新模型前，估計用量（目錄大小 × 1.2）
超過上限就從最久沒用的開始卸載，卸載後 `gc.collect()`＋`mx.clear_cache()`。
上限預設 16 GB，可在設定調整（4～40 GB）。正在用的那一個永遠不會被卸載。

## 6. 下載（`models.py`）

- 下載跑在子程序：`python -I -c <下載程式> <repo...>`。子程序先算總大小印出來，再逐一 `snapshot_download`。
  **為什麼用子程序**：`snapshot_download` 在執行緒裡停不下來；子程序可以直接終止，取消才做得到。
- 進度：父程序每次被問到時，量快取裡該模型 `blobs/` 的大小（含 `.incomplete`）除以總大小。
- 已下載的判斷：`refs/main` 指到的快照存在、`blobs/` 沒有 `.incomplete`。目錄的附屬模型（`extra_repos`）也要齊。
- 取消：終止子程序；未完成的檔案留著，下次下載會續傳。
- 刪除：先卸載，再刪除快取中該模型的資料夾；附屬模型若有其他已下載模型在用就保留。
- 測試時用環境變數 `VOICE_STUDIO_DOWNLOADER` 換成假的下載程式（照 Hugging Face 快取格式寫檔）。

## 7. 自訂模型

`POST /api/models/custom {"repo": "..."}`：抓該模型的 `config.json`，用 mlx-audio 的
對照表找出模型家族；只接受已有轉接器的家族，能力照家族範本推導。
Qwen3-TTS 依 `tts_model_type` 判斷是仿聲（base）、配音員（custom_voice，配音員名單取自 `spk_id`）
還是聲音描述（voice_design）。存在 `settings.json`，可刪除。

## 8. REST API（新增與變更）

| 方法 | 路徑 | 說明 |
|---|---|---|
| GET | `/api/models` | 全部模型與狀態（下載進度、是否在記憶體、是否為預設） |
| POST | `/api/models/{id}/download` | 開始下載 |
| DELETE | `/api/models/{id}/download` | 取消下載 |
| DELETE | `/api/models/{id}` | 刪除模型檔案（自訂模型同時移出清單） |
| POST | `/api/models/{id}/load`、`/unload` | 載入、卸載 |
| POST | `/api/models/custom` | 加入自訂模型 |
| GET | `/api/voices` | 聲音庫（含逐字稿、長度）＋照唸稿；保留 `voices` 欄位格式相容 |
| PATCH／DELETE | `/api/voices/{name}` | 改名稱、逐字稿；刪除 |
| POST | `/api/jobs` | 送出（可帶 `models` 批次） |
| GET | `/api/jobs` | 進行中與最近的工作 |
| DELETE | `/api/jobs/{id}` | 取消 |
| POST | `/api/history/{id}/voice` | 把成品存成聲音 |
| POST | `/api/history/restore` | 還原刪除的紀錄（復原用） |
| GET／PUT | `/api/settings` | 預設模型、記憶體上限 |
| GET／PUT | `/api/pronounce` | 另外回傳／接受 `rules` 陣列 |

## 9. MCP

- 新增 `list_models`：已下載的模型與能力。
- `synthesize` 新增選填參數 `model`、`mode`、`speaker`，舊參數不變。
- `list_voices` 回傳聲音庫與各已下載模型的配音員，代號格式不變。

## 10. 測試設計

- `VOICE_STUDIO_FAKE=1`：模型載入換成假模型（依文字長度產生正弦波，並記下收到的參數），
  讓轉接器、佇列、取消、紀錄都能在幾秒內測完。
- API 測試起一個真的 uvicorn 子程序（假引擎＋臨時資料夾＋臨時快取），用 `urllib` 打。
  不用 `TestClient`，因為鎖定的依賴裡沒有 `httpx`（憲法 A5）。
- 慢速測試（`VOICE_STUDIO_SLOW=1`）：對每個已下載的目錄模型真的產生一句中文，
  用本機 Breeze ASR 轉回文字，錯字率要低於門檻。
