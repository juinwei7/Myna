"""測試共用環境：臨時資料夾、臨時模型快取、假引擎、假下載程式（憲法 C2）。

必須在任何 `studio.*` 模組載入前設定好環境變數，所以放在測試套件的 __init__。
"""
import atexit
import os
import shutil
import tempfile
from pathlib import Path

_TMP = Path(tempfile.mkdtemp(prefix="voice-studio-test-"))
HOME = _TMP / "home"
CACHE = _TMP / "hf"
HERE = Path(__file__).parent

SLOW = os.environ.get("VOICE_STUDIO_SLOW") == "1"

os.environ.update({"VOICE_STUDIO_HOME": str(HOME), "VOICE_STUDIO_PORT": "18790"})
if not SLOW:
    # 慢速測試要用真的模型，所以只有快速測試換掉模型快取與引擎
    os.environ.update({
        "HF_HUB_CACHE": str(CACHE),
        "VOICE_STUDIO_FAKE": "1",
        "VOICE_STUDIO_DOWNLOADER": str(HERE / "fake_downloader.py"),
    })
atexit.register(shutil.rmtree, _TMP, True)
