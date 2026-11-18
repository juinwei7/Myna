# Spec 002 — 任務拆解

- [x] T1 — 命名「九官鳥」與新圖示（`make-icon.swift`、`Info.plist`、Makefile）
- [x] T2 — 拆成 `VoiceStudioCore`＋執行檔＋測試 target
- [x] T3 — `APITypes`、`StudioClient` 對上 Spec 001 的 API
- [x] T4 — 純邏輯與測試：`ComposerLogic`、`Formatting`、`Waveform`、`JobTracker`
- [x] T5 — `StudioModel`：狀態、輪詢、產生／取消／比較、復原
- [x] T6 — 側欄導覽與「產生」頁（稿子、檢閱器、最近產出）
- [x] T7 — 播放列與波形
- [x] T8 — 「音檔」表格
- [x] T9 — 「聲音庫」：清單、詳情、新增、編輯、刪除
- [x] T10 — 「模型」：下載、進度、取消、載入／卸載、預設、刪除、自訂模型
- [x] T11 — 偏好設定：一般、發音字典表格、服務
- [x] T12 — 選單列指令與快捷鍵、選單列圖示
- [x] T13 — 系統整合：服務選單、開啟文字檔、Dock
- [x] T14 — `BackendSupervisor`：`-m studio.app`、未打包時的退路
- [x] T15 — 打包、截圖驗收
- [x] T16 — 視覺語言：主色、宋體標題、單色側欄、文字樣式的動作、音檔詳情頁、這份稿子的版本、播放倍速
- [x] T18 — 設定改成側欄式視窗（六頁、可搜尋）＋每頁工具列的齒輪；主要按鈕只留一顆；側欄改列「最近的稿子」
- [x] T17 — 安裝後實際操作驗收

## 實作期間的發現

- **直接送終止訊號給 app 不會經過正常結束流程**，內附的後端會變成孤兒。兩邊都補：app 攔 SIGTERM／SIGINT 走正常結束，
  後端另外監看 app 的 PID（app 被 `kill -9` 也收得掉）。驗收 C3、C5。
- **清單的列裡不能放 SwiftUI 按鈕**（表格的點擊會被延後，憲法 U7）：側欄與「這份稿子的版本」都改成自己排的列。
- **系統的側欄清單會拿強調色畫圖示與選取列**，要單色只能自己排。
- **滑桿的最小／最大標籤會被主色染色**，改放在滑桿外面。
- **測試用的 app 要用獨立的偏好設定**（`VOICE_STUDIO_HOME` 有設時改用 `local.weiwei.voicestudio.test`），
  否則會把正式使用中的稿子蓋掉。
- **停測試服務要用連接埠找 PID**，不能用程序名稱比對：使用中的那一份名稱幾乎一樣。
- **截圖驗收用的啟動參數**：`-section`、`-appearance light|dark`、`-openSettings YES`、`-playLatest YES`（靜音）、`-detail <代號>`。
