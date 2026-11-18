"""驗收 G：真模型。對每個已下載的目錄模型實際產生一句中文。

    VOICE_STUDIO_SLOW=1 .venv/bin/python -m unittest studio.tests.test_slow_models

模型快取用真的（只讀），資料夾是臨時的。參考聲音從 app 的聲音庫複製第一個過來，
也可以用 VOICE_STUDIO_TEST_VOICE 指定（給 .wav 的路徑，旁邊要有同名的 .txt 逐字稿）。

有 mlx_whisper 的話會把成品轉回文字算錯字率：
    VOICE_STUDIO_ASR_PYTHON=<裝了 mlx_whisper 的 python>
    VOICE_STUDIO_ASR_MODEL=<Whisper 模型的資料夾或 Hugging Face 名稱>
沒設定就只檢查每個模型都產得出長度合理的音檔。
"""
import json
import os
import re
import shutil
import subprocess
import unittest
from pathlib import Path

from studio import catalog, config, models
from studio.tests import SLOW

SENTENCE = "歡迎使用語音工作室，今天我們來介紹幾個新的語音模型。"
MAX_CER = 0.15
ASR_PYTHON = os.environ.get("VOICE_STUDIO_ASR_PYTHON")
ASR_MODEL = os.environ.get("VOICE_STUDIO_ASR_MODEL")
APP_VOICES = Path.home() / "Library/Application Support/VoiceStudio/voices"
ASR_SCRIPT = """
import json, sys, mlx_whisper
print(json.dumps({p: mlx_whisper.transcribe(p, path_or_hf_repo=sys.argv[1], language="zh")["text"]
                  for p in sys.argv[2:]}, ensure_ascii=False))
"""


def reference_voice():
    given = os.environ.get("VOICE_STUDIO_TEST_VOICE")
    if given:
        return Path(given)
    return next((w for w in sorted(APP_VOICES.glob("*.wav")) if w.with_suffix(".txt").exists()), None)


def cer(ref, hyp):
    ref, hyp = (re.sub(r"[^\w]", "", s) for s in (ref, hyp))
    d = list(range(len(hyp) + 1))
    for i, a in enumerate(ref, 1):
        prev, d[0] = d[0], i
        for j, b in enumerate(hyp, 1):
            prev, d[j] = d[j], min(d[j] + 1, d[j - 1] + 1, prev + (a != b))
    return d[-1] / max(1, len(ref))


def transcribe(paths):
    out = subprocess.run([ASR_PYTHON, "-W", "ignore", "-c", ASR_SCRIPT, ASR_MODEL, *paths],
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out.strip().splitlines()[-1])


@unittest.skipUnless(SLOW, "設 VOICE_STUDIO_SLOW=1 才跑真模型")
class RealModelTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        config.ensure_dirs()
        source = reference_voice()
        if not source:
            raise unittest.SkipTest("找不到參考聲音：先在 app 新增一個聲音，或設 VOICE_STUDIO_TEST_VOICE")
        shutil.copy(source, config.VOICES / "ref.wav")
        shutil.copy(source.with_suffix(".txt"), config.VOICES / "ref.txt")

    def test_g1_every_downloaded_model_speaks_chinese(self):
        from studio.engine import Engine
        from studio.resolve import resolve

        engine = Engine()
        made = {}
        for spec in catalog.CATALOG:
            if not models.is_downloaded(spec):
                print(f"  略過 {spec.id}（未下載）")
                continue
            for mode in spec.modes:
                payload = {"text": SENTENCE, "model": spec.id, "mode": mode}
                if mode == "clone":
                    payload["voice"] = "ref"
                elif mode == "preset":
                    payload["speaker"] = "Vivian"
                else:
                    payload["instruct"] = "女性，青年，中音" if spec.family == "omnivoice" \
                        else "一位三十歲左右的台灣女性，聲音溫暖親切，語速適中。"
                rec = engine.synth(resolve(payload))
                made[rec["path"]] = (spec.id, mode, rec["seconds"])
            engine.unload(spec.id)
        self.assertTrue(made, "沒有任何已下載的模型")

        for path, (model_id, mode, seconds) in made.items():
            self.assertTrue(2 < seconds < 20, f"{model_id}/{mode} 的長度不合理：{seconds} 秒")
        if not (ASR_PYTHON and ASR_MODEL):
            for model_id, mode, seconds in made.values():
                print(f"  {model_id:20s} {mode:7s} {seconds:5.1f} 秒")
            print("  沒有設定語音辨識，略過錯字率")
            return
        texts = transcribe(list(made))
        failures = []
        for path, (model_id, mode, seconds) in made.items():
            rate = cer(SENTENCE, texts[path])
            print(f"  {model_id:20s} {mode:7s} {seconds:5.1f} 秒  錯字率 {rate:.0%}  {texts[path].strip()}")
            if rate > MAX_CER:
                failures.append(f"{model_id}/{mode} 錯字率 {rate:.0%}")
        self.assertEqual(failures, [])

    def test_g2_native_speed_changes_length(self):
        from studio.engine import Engine
        from studio.resolve import resolve

        spec = catalog.builtin("omnivoice")
        if not models.is_downloaded(spec):
            self.skipTest("OmniVoice 未下載")
        engine = Engine()
        base = {"text": SENTENCE, "model": "omnivoice", "voice": "clone:ref"}
        normal = engine.synth(resolve(base))["seconds"]
        slow = engine.synth(resolve({**base, "speed": 0.8}))["seconds"]
        self.assertAlmostEqual(slow / normal, 1.25, delta=0.1)


if __name__ == "__main__":
    unittest.main()
