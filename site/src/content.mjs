// 官網的文字（docs/website.md §4）。跟 app 用同樣的詞：仿聲、配音員、聲音描述、聲音庫、發音字典。
// 模型的表跟 studio/catalog.py、README 是同一份資料，改了要三邊一起改。

import { REPO } from './releases.mjs';

export const GITHUB = `https://github.com/${REPO}`;

export const MODELS = [
  { name: 'Qwen3-TTS 1.7B 仿聲', modes: '仿聲', size: '4.5 GB', license: 'Apache-2.0', cer: '0%', note: '中文最穩，連說話速度都會學參考錄音' },
  { name: 'Qwen3-TTS 1.7B 配音員', modes: '配音員', size: '4.5 GB', license: 'Apache-2.0', cer: '0%', note: '9 位配音員，可以指定語氣；中文口音偏中國大陸' },
  { name: 'Qwen3-TTS 1.7B 聲音描述', modes: '聲音描述', size: '4.5 GB', license: 'Apache-2.0', cer: '0%', note: '' },
  { name: 'Qwen3-TTS 0.6B 仿聲', modes: '仿聲', size: '2.0 GB', license: 'Apache-2.0', cer: '0%', note: '輕量版，記憶體用量少一半以上' },
  { name: 'Breeze-TTS 2', modes: '仿聲、聲音描述', size: '4.6 GB', license: '研究與非商業', cer: '0%', note: '仿聲時可以用一句話指揮語氣；不能商用' },
  { name: 'VoxCPM2', modes: '仿聲、聲音描述', size: '3.2 GB', license: 'Apache-2.0', cer: '0%', note: '48 kHz' },
  { name: 'OmniVoice', modes: '仿聲、聲音描述', size: '1.6 GB', license: 'Apache-2.0', cer: '0%', note: '最快，語速由模型自己控制' },
  { name: 'MOSS-TTS Nano', modes: '仿聲', size: '0.4 GB', license: 'Apache-2.0', cer: '8%', note: '最小，適合試稿，不適合當成品' },
];

export const content = {
  name: '九官鳥',
  fullName: '九官鳥 Myna',
  title: '九官鳥 Myna：Mac 上的文字轉語音 app，可以用自己的聲音',
  description: '寫好稿子，選一個聲音和模型，在你的 Mac 上唸成音檔。錄十秒就能用自己的聲音，8 個開源語音模型自己挑，稿子和錄音都不會上傳。免費、開源。',
  nav: { features: '功能', models: '模型', privacy: '隱私', download: '下載', changelog: '版本說明', github: 'GitHub' },
  intro: {
    heading: 'Mac 上的文字轉語音 app',
    text: '寫好稿子，選一個聲音和模型，在你的 Mac 上唸成音檔。錄十秒，它就能用你的聲音唸。',
    download: (version) => (version ? `下載九官鳥 ${version}` : '下載與安裝'),
    source: '在 GitHub 看原始碼',
    small: '免費、開源，需要 Apple Silicon 和 macOS 14 以上',
  },
  shots: {
    studio: '九官鳥的產生頁：中間是稿子，下面列出同一份稿子用三個模型產生的版本，右邊選聲音和模型，底部是有波形的播放列',
    voices: '聲音庫：左邊是聲音的清單，右邊是台灣女聲的長度、試聽和逐字稿',
    versions: '一個音檔的詳情：這份稿子的三個版本排在一起，各自標著模型和長度，下面是稿子全文',
    models: '模型頁：上面是記憶體用量，下面每個模型列出能做什麼、大小、授權，不能商用的有標示',
  },
  features: {
    heading: '寫稿子，選聲音，按一下',
    paragraphs: [
      '稿子寫在中間。換行會分段唸，空一行會停久一點。按 ⌘↩ 就開始產生，做完自動播放。',
      '聲音有三種來源，在工具列中間切換。「仿聲」照你錄的參考錄音唸；「配音員」是模型內建的聲音，可以加一句語氣，像「親切、清楚的車站廣播」；「聲音描述」是用文字形容，像「三十歲左右的台灣女性，聲音溫暖親切」。',
      '做好的音檔可以直接拖到 Finder、剪輯軟體或聊天視窗。',
    ],
  },
  voices: {
    heading: '用你自己的聲音唸',
    paragraphs: [
      '到聲音庫按新增，照著畫面上那段字唸十秒左右。存好之後，這個聲音就能拿來唸任何稿子。也可以直接拖一段現成的錄音進來，再把它的逐字稿補上。',
      '聲音跟模型是分開的。同一個聲音可以換不同的模型試，聽哪個最像。',
      '用聲音描述試到一個滿意的音色時，可以把那次的成品存進聲音庫，之後用仿聲重現它。聲音描述每次產生的音色都不太一樣，不存下來就找不回來。',
    ],
    note: '仿聲很容易被拿來冒充別人。請只錄你自己的聲音，或已經取得對方同意的聲音。',
  },
  compare: {
    heading: '同一份稿子，換個模型再聽一次',
    paragraphs: [
      '同一個聲音、同一份稿子，換一個模型唸出來的味道就不一樣。打開「比較模型」勾幾個，同一份稿子會各產生一次。',
      '做完的版本排在稿子下面，標著是哪個模型、多長，點一下就播。稿子沒改，之前試過的版本都會留在這一排。',
    ],
  },
  models: {
    heading: '8 個模型，要用哪個自己挑',
    paragraphs: [
      '模型不在 app 裡，是你在「模型」頁自己下載的。下載看得到進度，可以取消，下次會接著下載。同時留在記憶體裡的模型超過上限時，最久沒用的會自動卸載。',
      '下面每個模型我都用同一句中文測過：產生之後用語音辨識轉回文字，算錯了幾個字。',
    ],
    columns: ['模型', '能做什麼', '大小', '授權', '錯字率', '說明'],
    note: '授權以各模型自己的頁面為準，要商用請自己再確認一次。app 裡不能商用的模型會標出來。',
  },
  privacy: {
    heading: '稿子和聲音都留在你的 Mac',
    text: '語音是在你的 Mac 上產生的，不經過任何伺服器。沒有帳號，也沒有使用統計。',
    stays: { title: '留在這台 Mac', items: ['你寫的稿子', '你錄的參考聲音和逐字稿', '產生的音檔', '發音字典和設定'] },
    leaves: { title: '會連到網路的時候', items: ['下載模型，連到 Hugging Face', '加入其他模型時，到 Hugging Face 查它的資料'] },
    note: '資料存在 ~/Library/Application Support/VoiceStudio，模型存在 Hugging Face 的快取資料夾。',
  },
  mcp: {
    heading: '讓 Claude 幫你唸',
    paragraphs: [
      '九官鳥開著的時候，支援 MCP 的 AI 工具可以直接叫它產生語音。Claude Code 在終端機加這一行：',
    ],
    command: 'claude mcp add --transport http myna http://localhost:8790/mcp',
    after: '之後就能跟 Claude 說「把這段公告唸成音檔」。它送來的工作會出現在九官鳥的佇列，做完的音檔也留在 app 裡。這個位址只有這台 Mac 自己連得到。',
  },
  download: {
    heading: '下載',
    requirements: [
      ['系統', 'macOS 14 以上，Apple Silicon（M1 之後的 Mac）'],
      ['空間', 'app 約 630 MB；模型另外算，一個 0.4 到 4.6 GB'],
      ['記憶體', '建議 16 GB 以上。最大的模型載入後大約佔 5 GB'],
      ['費用', '免費，原始碼用 MIT 授權公開'],
    ],
    button: (version) => `下載九官鳥 ${version}（DMG）`,
    firstTitle: '第一次打開',
    firstText: '我沒有 Apple 開發者帳號，app 沒有經過 Apple 簽章，第一次打開會被系統擋下來。',
    steps: [
      '打開九官鳥，跳出警告時按「完成」。',
      '到「系統設定 → 隱私權與安全性」，往下找到九官鳥，按「強制打開」。',
      '之後就能正常打開。第一次進去會請你挑一個模型下載。',
    ],
    none: '安裝檔還沒有發布，現在要從原始碼建置。需要先裝 Xcode 的命令列工具（xcode-select --install）。',
    sourceTitle: '從原始碼建置',
    sourceText: '想自己建的話，需要 Xcode 的命令列工具。make app 會下載一份可攜的 Python 和需要的套件，一起包進 app，第一次約 650 MB。',
    sourceCommands: `git clone ${GITHUB}.git\ncd Myna/mac\nmake app\nmake install`,
  },
  faq: {
    heading: '常見問題',
    items: [
      ['產生的音檔可以商用嗎？', '看你用哪個模型。Breeze-TTS 2 的授權只限研究和非商業用途，app 裡會標出來。其他幾個是 Apache-2.0，一般可以商用，但請以模型自己的頁面為準。另外，聲音本身也要是你有權使用的。'],
      ['需要網路嗎？', '只有下載模型時需要。模型下載好之後，拔掉網路也能產生語音。'],
      ['Intel 的 Mac 可以用嗎？', '不行。這些模型是用 Apple 的 MLX 跑的，只支援 Apple Silicon。'],
      ['唸出來太快怎麼辦？', '仿聲會連參考錄音的說話速度一起學，錄音講得快，成品就快。可以拉右邊的語速、換 OmniVoice（它的語速是模型自己控制的），或重錄一段講慢一點的參考錄音。'],
      ['有字唸錯怎麼辦？', '到設定的「發音字典」加一組：左邊寫稿子裡的寫法，右邊寫一個唸起來對的寫法。之後稿子不用改，產生時會自動換。'],
      ['可以仿別人的聲音嗎？', '技術上有錄音就能仿，但請只用你自己的聲音，或已經取得對方同意的聲音。'],
      ['有英文介面嗎？', '目前只有繁體中文。稿子可以是中文、英文、日文或韓文，看模型支援哪些。'],
      ['跟 macOS 內建的朗讀有什麼不同？', '內建的朗讀只能用系統附的聲音。九官鳥可以用你自己的聲音、可以換模型比較，產生的是可以拿去剪輯的音檔。'],
    ],
  },
  changelog: {
    title: '版本說明',
    description: '九官鳥每一版改了什麼。',
    latest: '最新版',
    download: '下載 DMG',
    onGitHub: '在 GitHub 上看',
  },
  notFound: { title: '找不到這一頁', text: '網址可能打錯了，或這一頁已經搬走。', home: '回首頁' },
  footer: '九官鳥 Myna，個人開源專案',
};
