"""路徑、連接埠與各種上限。

全部可用環境變數覆寫（憲法 A3）：測試指向臨時資料夾，app 版指向 Application Support。
模型快取沿用 Hugging Face 的 `HF_HUB_CACHE`／`HF_HOME`，由 huggingface_hub 自己讀。
"""
import os
import shutil
from pathlib import Path

# 預設跟 app 用同一個資料夾：從原始碼啟動後端時，看到的聲音、音檔跟 app 裡一樣
ROOT = Path(os.environ.get("VOICE_STUDIO_HOME")
            or (Path.home() / "Library/Application Support/VoiceStudio"))
VOICES = ROOT / "voices"
OUT = ROOT / "out" / "studio"
HISTORY = OUT / "history.jsonl"
PRONOUNCE = ROOT / "pronounce.txt"
SETTINGS = ROOT / "settings.json"
SCRIPT = ROOT / "script.txt"
# 產生途中先做好的段落（邊產生邊播用），暫存：服務啟動時清空
PARTS = ROOT / "parts"
HERE = Path(__file__).parent

PORT = int(os.environ.get("VOICE_STUDIO_PORT", "8790"))
BASE_URL = f"http://localhost:{PORT}"

# ffmpeg 是選配：有它才能用 atempo 調語速、讀 webm 這類 macOS 不認得的格式；格式轉換沒有它就用 macOS 內建的 afconvert
FFMPEG = shutil.which("ffmpeg") or next(
    (p for p in ("/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg") if os.path.exists(p)), None)

MAX_CHARS = 5000
# MCP 的呼叫端（或中間的閘道）常見的逾時是 20～30 秒；最多等 15 秒，沒做完就回 job_id 讓對方再查
MCP_WAIT_SECONDS = 15
# 工作結束後分段成品再留多久（秒）：app 換成完整音檔之前可能還在播最後幾段
PARTS_KEEP_SECONDS = 3600

# 測試用：換成假模型與假下載程式，不載入 MLX
FAKE_ENGINE = os.environ.get("VOICE_STUDIO_FAKE") == "1"
DOWNLOADER = os.environ.get("VOICE_STUDIO_DOWNLOADER")  # 下載程式的路徑；沒設就用內建的

DEFAULT_SCRIPT = "今天天氣還不錯，我想跟大家分享最近在做的一件事。"
DEFAULT_PRONOUNCE = "# 左邊是稿子裡的寫法，右邊是要唸的寫法，一行一組（例：山嵐=山藍）\n"


def ensure_dirs():
    for d in (VOICES, OUT):
        d.mkdir(parents=True, exist_ok=True)
    if not PRONOUNCE.exists():
        PRONOUNCE.write_text(DEFAULT_PRONOUNCE, encoding="utf-8")
