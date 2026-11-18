# Spec 003 — 實作計畫

## 1. 後端

### 分段成品（`engine.py`、`jobs.py`）

`Engine.synth` 原本把每一段的聲音收在記憶體，最後接起來存檔，語速（ffmpeg atempo）對整個檔案做一次。
改成**每一段各自處理完**（聲音＋段後的停頓＋語速），再交給呼叫端：

```
for 每一段:
    piece = 模型產生的聲音 + 停頓
    piece = 調語速（需要的話）
    on_part(第幾段, 總段數, piece, 取樣率)      # 只有兩段以上才呼叫
    pieces.append(piece)
成品 = 接起來(pieces)
```

成品就是各段接起來，所以「先播的那幾段」跟成品裡同一個位置的聲音完全相同，
app 才能在整份做完之後換成完整的音檔、接在同一個位置。

調語速要 ffmpeg；沒有就在迴圈開始前丟錯（約束 C-3）。

`Jobs._run` 提供 `on_part`：寫成 `parts/<工作代號>/0001.wav`（先寫暫存檔再改名，app 不會讀到寫一半的檔），
然後把 `job.parts` 加一。工作的檢視多四個欄位：

| 欄位 | 說明 |
|---|---|
| `speak` | 做好要直接播（來自 `speak`） |
| `segments` | 總段數（開始產生後才有） |
| `parts` | 已經做好、可以播的段數 |
| `parts_dir` | 分段成品的資料夾 |

清理：服務啟動時清空 `parts/`；每次有工作開始跑時，順手刪掉結束超過一小時的；取消或失敗的當下就刪。

### 直接唸出來（`app.py`、`settings.py`）

- `settings.allow_speak`（布林，預設 true），`view()`、`update()` 都加。
- `speak_now(payload)`：`allow_speak` 關著就丟 `ValueError`；否則照 `submit` 排進去，工作標上 `speak`，立刻回傳。
- MCP 工具 `speak(text, voice, model, instruct, speed)` 與 `POST /api/speak` 都呼叫它。

## 2. app

### 播放器（`Audio.swift`）

`Player` 多一個「邊做邊播」的狀態 `live`：

```
startLive(id, title, subtitle)      開始：停掉原本在播的
feed(id, parts: [URL], total)       後端又做好幾段：補進清單；正在等就接著播
complete(id, final: Playable)       整份做完：下一個段落的交界換成完整音檔（暫停中就馬上換）
```

每一段用一個 `AVAudioPlayer`。一段播完：有下一段就播；沒有而且還沒做完就等（`live.waiting`）；
已經做完就載入完整音檔、跳到「已播各段的長度總和」繼續。段尾本來就有停頓，換播放器的那幾毫秒聽不出來。

邊做邊播時不能跳轉（後面的還不存在），暫停、倍速照常。播別的東西、`stop()`、`clear()` 都會結束這個狀態。

決定「現在該播什麼」的邏輯抽成純函式（`LiveLogic`），才測得到。

### 狀態（`StudioModel.swift`）

每次輪詢：

1. 自己送出的那一筆（`autoplayJob`）而且自動播放開著：`parts ≥ 1` 就開始邊做邊播，之後每次把新的段落餵進去。
2. `speak` 的工作：第一次看到就排進 `speakQueue`。播放器閒著（沒在播、也沒在邊做邊播）時取出最前面那筆：
   還在產生而且有段落 → 邊做邊播；已經做完 → 直接播成品；失敗或取消 → 跳過。
3. 工作結束：正在邊做邊播的那一筆 → `complete`；取消或失敗 → 停止播放。

app 剛打開時已經存在的 `speak` 工作不播（跟 `JobTracker` 同樣的道理）。

### 介面

- **播放列**：邊做邊播時，波形的位置換成段落進度條（已播、已做好、還沒做），右邊的總長度換成「產生中」；
  副標寫「已做好 3／8 段」。不能拖曳跳轉。
- **設定 → AI 工具**：開關「讓 AI 工具直接唸出來」，下面一行說明。指令清單補上 `speak`。
- **設定 → 產生**：「自動播放」的說明改成會提到分段。
- **選單列**：有東西在播時多一項「停止播放」。

## 3. 官網

### 試聽的音檔（`site/make-samples.py`）

對一個**測試用的服務**（預設 `http://127.0.0.1:8791`，暫存資料夾）送工作，不碰使用者的資料：

1. Qwen3 聲音描述、Breeze-TTS 2、VoxCPM2、OmniVoice：用同一句聲音描述產生。
2. Qwen3 配音員：內建配音員加一句語氣。
3. 把第 1 步 Qwen3 聲音描述的成品存成聲音（`POST /api/history/{id}/voice`），
   Qwen3 仿聲 1.7B、0.6B、MOSS-TTS Nano 用它當參考錄音。
4. 每個成品用 macOS 內建的 `afconvert` 轉成 AAC（單聲道、64 kbps），放進 `site/public/audio/<模型代號>.m4a`。

音檔進 git（`.gitignore` 對 `site/public/audio/` 開例外），CI 在 Linux 建置網站時不需要模型。

### 頁面

- `content.mjs` 多一份 `SAMPLES`（模型代號、名稱、怎麼做的）與那一句稿子。
- `pages.mjs` 在比較那一節的截圖下面排成兩欄的清單，每筆是名稱、做法、`<audio controls preload="none">`。
- `build.mjs` 檢查每個 `SAMPLES` 都有對應的檔案，缺了就建置失敗。
- `_headers` 的內容安全政策確認允許同源的音檔。

### 文案跟著版本走（約束 C-4）

段落可以寫成 `{ since: '2.1.0', text: '…' }`；`pages.mjs` 拿最新發布的版本比，還沒到就不放。

## 4. 版本

app 版本 2.1.0（`Info.plist`、Makefile 的 DMG 檔名）。
