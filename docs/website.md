# 九官鳥官網：需求與設計（已上線 https://myna.weibuilds.com）

repo 是 `github.com/juinwei7/Myna`。網址和 repo 名稱各只寫在一個地方
（`site/build.mjs` 的 `SITE_URL` 預設值、`site/src/releases.mjs` 的 `REPO`）。

## 1. 需求

給誰看：在 Mac 上要把文字唸成音檔的人，例如做影片旁白、產品介紹、廣播稿、有聲內容的人；
以及在社群看到分享點進來、要在 10 秒內看懂「這是什麼、能不能用」的人。

- W1 一眼看懂：第一屏說清楚「Mac 上的文字轉語音 app，可以用自己的聲音」，並且可以下載。
- W2 說清楚哪裡不同：語音在本機產生、可以仿自己的聲音、8 個模型自己挑、同一份稿子可以換模型比較。
- W3 模型的底細：每個模型能做什麼、多大、什麼授權、能不能商用、中文測出來的錯字率。
- W4 下載：按鈕指向最新版的 DMG；旁邊寫系統需求，和第一次打開要怎麼做（沒有 Apple 簽章）。
  還沒有發布安裝檔時，改成教人從原始碼建置。
- W5 版本說明：發布新版後自動出現，不用另外改網站。
- W6 隱私：哪些東西留在這台 Mac、什麼時候會連網，講清楚。
- W7 提醒：仿聲只用自己或已取得同意的聲音。
- W8 分享出去好看：有標題、說明和預覽圖。
- W9 基本品質：手機也能看、深色模式、鍵盤可以操作、開啟快、不用 cookie、不追蹤訪客。

不做：英文版（app 目前只有繁體中文介面）、部落格、帳號、留言、網站分析、首屏的互動示範。

| 頁面 | 網址 | 內容 |
|---|---|---|
| 首頁 | `/` | 一句話介紹、截圖、怎麼用、模型、隱私、MCP、下載、常見問題 |
| 版本說明 | `/changelog/` | 每一版的更新內容（有發布版本才有這一頁） |
| 下載 | `/download` | 轉到最新版的 DMG，給 README、社群貼文用的固定連結 |
| 找不到頁面 | 404 | 說明找不到，給回首頁的連結 |

## 2. 文案

講清楚做什麼，不堆形容詞。跟 app 用同樣的詞（仿聲、配音員、聲音描述、聲音庫、發音字典）。
用「我」，講實際做過的事和實際的數字（「每個模型我都用同一句中文測過」）。

避免：排比的口號、「不是 X，是 Y」、冒號後面揭示、結尾的保證句、「強大」「無縫」「一站式」這類詞。

## 3. 定版

像開發者自己寫的 Mac app 產品頁：

- 白底（深色模式深灰），柿橘**只**用在下載按鈕和連結
- 只用系統字體，不載入網路字型；內文 17px、行高 1.75；標題 40（手機 30）／26／17px
- 一欄由上往下讀的說明文（最寬 680px），**真的截圖**比文字寬一點（最寬 960px），跟著說明出現
- 第一屏置中（圖示、標題、一句說明、下載按鈕），其他內容靠左
- 避免：大寫英文小標籤、`A · B · C` 中黑點串接、按鈕後面加「→」、接近黑的 #111、捲動時淡入或懸停浮起的動畫
- 整個網站**沒有 JavaScript**：深色模式跟著系統，常見問題用 `<details>`

| 名稱 | 淺色 | 深色 | 用在哪裡 |
|---|---|---|---|
| 背景 | #FFFFFF | #1C1C1E | 頁面 |
| 文字 | #1D1D1F | #F2F2F7 | 內文、標題 |
| 次要文字 | #6E6E73 | #98989F | 說明、表頭、頁尾 |
| 線 | #E5E5EA | #38383A | 分隔線 |
| 淺底 | #F5F5F7 | #2C2C2E | 指令區塊 |
| 柿橘 | #C2512C | #F28C5E | 下載按鈕、連結、焦點框 |

深色模式的下載按鈕用深色字（#2A1208），對比才夠。

## 4. 首頁的順序

1. 圖示、標題「Mac 上的文字轉語音 app」、一句說明、下載與 GitHub 兩顆按鈕、系統需求
2. 產生頁的截圖
3. 寫稿子，選聲音，按一下
4. 用你自己的聲音唸（聲音庫的截圖；仿聲的提醒）
5. 同一份稿子，換個模型再聽一次（音檔詳情的截圖）
6. 8 個模型，要用哪個自己挑（模型頁的截圖、模型的表）
7. 稿子和聲音都留在你的 Mac（留在 Mac／會連網的時候，兩欄）
8. 讓 Claude 幫你唸（MCP 的指令）
9. 下載（需求、DMG、第一次打開、從原始碼建置）
10. 常見問題

模型的表跟 `studio/catalog.py`、README 是同一份資料，改了要三邊一起改。

## 5. 技術

- 不用框架，一支沒有相依套件的 Node 程式（`site/build.mjs`，Node 20 以上）產生靜態網頁到 `site/dist/`。
- 檔案：
  - `site/src/content.mjs`：所有文字、模型的表
  - `site/src/pages.mjs`：首頁、版本說明、404 的 HTML、`llms.txt`
  - `site/src/releases.mjs`：讀 GitHub Releases；讀不到或還沒有發布就回空的
  - `site/src/style.css`：建置時直接寫進每一頁
  - `site/public/`：favicon、分享預覽圖、截圖的 AVIF、`_headers`，原樣複製
  - `site/serve.mjs`：本機預覽（http://localhost:4322/）
  - `site/make-images.sh`：把 `docs/images` 的截圖轉成 AVIF、產生 favicon、用 `site/og.html` 截分享預覽圖
- 截圖只有一份來源，是 README 用的 `docs/images`。網頁優先用 AVIF（原寬和 960 寬兩種，品質 60），PNG 當備援。
  截圖的長寬要是偶數、而且縮到 960 寬時高也要是偶數（1920×1168 可以），不然 `sips` 轉出來的 AVIF 在 Safari、Firefox 是空白的。
- 截圖用示範資料拍，不用真的稿子和聲音。
- 發布說明的格式（tag 的說明會變成 Release 的內文）：第一行「九官鳥 X.Y.Z：副標」，接著一行一條、用「- 」開頭；
  空一行之後可以放英文段，網站只讀中文那一段。
- SEO：標題、說明、canonical、`sitemap.xml`、`robots.txt`、`llms.txt`、Open Graph（1200×630）、SoftwareApplication 的結構化資料。
- `_headers`：`nosniff`、Referrer-Policy、CSP（不允許任何 script）、圖片快取一天。

## 6. 部署

Cloudflare Pages 的專案叫 `myna`（直接上傳的專案，Cloudflare 給的網址是 `myna-1ar.pages.dev`），
自訂網域 `myna.weibuilds.com` 是一筆指到它的 CNAME。`*.pages.dev` 的網址帶 `X-Robots-Tag: noindex`，不讓搜尋引擎收。

`.github/workflows/site.yml`：推到 main 改到網站或截圖、發布新版、或手動執行時建置；
有設定 `CLOUDFLARE_API_TOKEN`、`CLOUDFLARE_ACCOUNT_ID` 才部署，沒有就只建置。

現況（2026-11-18）：

- 第一次上線是在 Cloudflare 後台手動上傳 `site/dist` 的壓縮檔。
- `CLOUDFLARE_ACCOUNT_ID` 已經設好；`CLOUDFLARE_API_TOKEN` **還沒設**，所以推上 main 或發布新版時網站還不會自動更新。
  設好之後（權限要有「帳戶 → Cloudflare Pages → 編輯」）手動跑一次「官網」流程確認。
- 在 token 設好之前要更新網站：`node site/build.mjs`，把 `site/dist` 壓成 zip，
  到 Cloudflare 後台的 Pages 專案 `myna` →「建立部署」上傳。

驗證線上的網站：

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://myna.weibuilds.com/            # 200
curl -s -o /dev/null -w '%{http_code}\n' https://myna.weibuilds.com/changelog/  # 200
curl -s -o /dev/null -w '%{redirect_url}\n' https://myna.weibuilds.com/download # 最新版的 DMG
```
