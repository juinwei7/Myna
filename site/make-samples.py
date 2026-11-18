#!/usr/bin/env python3
"""產生官網的試聽音檔：8 個模型各唸同一句話，放進 site/public/audio/。

要先起一個測試用的語音服務（暫存資料夾，不要用平常在用的那一份），模型要都下載好：

    VOICE_STUDIO_HOME=/tmp/myna-demo VOICE_STUDIO_PORT=8791 .venv/bin/python -m studio.app &
    python3 site/make-samples.py --base http://127.0.0.1:8791
    python3 site/make-samples.py --base http://127.0.0.1:8791 --only omnivoice,moss-tts-nano   # 只重做這幾個

不用任何真人的聲音：聲音描述、內建配音員，或是拿聲音描述的成品當參考錄音去仿。
句子、聲音描述、每個模型怎麼做，都跟 site/src/content.mjs 的 SAMPLES 對著寫，改了要兩邊一起改。
只用標準庫；轉檔用 macOS 內建的 afconvert。做完會把自己產生的紀錄和聲音從那個服務刪掉。

模型每次產生的結果不太一樣。做完用語音辨識檢查一次（specs/003 的驗收 D4），有唸錯字的用 --only 重做：

    VOICE_STUDIO_ASR_PYTHON=<裝了 mlx_whisper 的 python> VOICE_STUDIO_ASR_MODEL=<Whisper 模型> \
      python3 site/make-samples.py --check
"""
import argparse
import json
import os
import re
import subprocess
import time
import urllib.request
from pathlib import Path

SENTENCE = "今天天氣還不錯，我想跟大家分享最近在做的一件事。"
DESIGN = "三十歲左右的台灣女性，聲音溫暖親切"
# OmniVoice 的聲音描述要用簡短的特徵詞；寫成一整句它會重複唸字
DESIGNED = {"qwen3-1.7b-design": DESIGN, "breeze-tts-2": DESIGN, "voxcpm2": DESIGN,
            "omnivoice": "女性，青年，中音"}
PRESET = {"model": "qwen3-1.7b-custom", "speaker": "Vivian", "instruct": "像在跟朋友聊天，輕鬆自然"}
CLONED = ["qwen3-1.7b-base", "qwen3-0.6b-base", "moss-tts-nano"]
# 給仿聲當參考錄音的那一段：用聲音描述產生，內容跟要唸的句子不一樣。
# 用 VoxCPM2 做：試過拿 Qwen3 聲音描述的成品當參考，Qwen3 仿聲會唸錯前幾個字
REFERENCE = "會議將在五分鐘後開始，請各位準備入座。資料已經放在桌上，有問題可以隨時提出來。"
REFERENCE_MODEL = "voxcpm2"

OUT = Path(__file__).parent / "public" / "audio"
MAX_CER = 0.15
ASR_SCRIPT = """
import json, sys, mlx_whisper
print(json.dumps({p: mlx_whisper.transcribe(p, path_or_hf_repo=sys.argv[1], language="zh")["text"]
                  for p in sys.argv[2:]}, ensure_ascii=False))
"""


def cer(ref, hyp):
    """錯字率：把兩邊的標點拿掉之後的編輯距離，除以原句的字數。"""
    ref, hyp = (re.sub(r"[^\w]", "", s) for s in (ref, hyp))
    d = list(range(len(hyp) + 1))
    for i, a in enumerate(ref, 1):
        prev, d[0] = d[0], i
        for j, b in enumerate(hyp, 1):
            prev, d[j] = d[j], min(d[j] + 1, d[j - 1] + 1, prev + (a != b))
    return d[-1] / max(1, len(ref))


def check(models):
    """把每個試聽音檔轉回文字，錯字率太高的列出來。"""
    python, asr = os.environ.get("VOICE_STUDIO_ASR_PYTHON"), os.environ.get("VOICE_STUDIO_ASR_MODEL")
    if not python or not asr:
        raise SystemExit("要先設 VOICE_STUDIO_ASR_PYTHON 與 VOICE_STUDIO_ASR_MODEL")
    files = [str(OUT / f"{m}.m4a") for m in models]
    out = subprocess.run([python, "-W", "ignore", "-c", ASR_SCRIPT, asr, *files],
                         capture_output=True, text=True, check=True).stdout
    heard = json.loads(out.strip().splitlines()[-1])
    bad = []
    for model, file in zip(models, files):
        rate = cer(SENTENCE, heard[file])
        print(f"  {model:20s} {rate * 100:5.1f}%  {heard[file].strip()}")
        if rate > MAX_CER:
            bad.append(model)
    if bad:
        raise SystemExit(f"錯字太多，重做：--only {','.join(bad)}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--base", default="http://127.0.0.1:8791", help="測試用語音服務的位址")
    parser.add_argument("--only", default="", help="只重做這幾個模型（用逗號分開模型代號）")
    parser.add_argument("--check", action="store_true", help="不產生，只用語音辨識檢查現有的音檔")
    args = parser.parse_args()
    base = args.base.rstrip("/")
    everything = [*DESIGNED, PRESET["model"], *CLONED]
    only = [m for m in args.only.split(",") if m] or everything
    if unknown := set(only) - set(everything):
        raise SystemExit(f"不認得的模型：{'、'.join(sorted(unknown))}")
    if args.check:
        return check(only)

    def call(method, path, body=None):
        req = urllib.request.Request(base + path, method=method,
                                     data=json.dumps(body).encode() if body is not None else None,
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.load(resp)

    def make(payload):
        job = call("POST", "/api/jobs", payload)
        while job["status"] in ("queued", "running"):
            time.sleep(0.5)
            job = call("GET", f"/api/jobs/{job['job_id']}")
        if job["status"] != "done":
            raise SystemExit(f"{payload.get('model')} 失敗：{job.get('error')}")
        print(f"  {job['model_name']}：{job['seconds']} 秒")
        return job

    home = call("GET", "/api/health")["home"]
    if "Application Support" in home:
        raise SystemExit(f"這個服務用的是平常在用的資料夾（{home}），請改用測試用的服務")
    missing = [m["id"] for m in call("GET", "/api/models")["models"]
               if m["id"] in [*only, REFERENCE_MODEL] and m["state"] != "downloaded"]
    if missing:
        raise SystemExit(f"這些模型還沒下載：{'、'.join(missing)}")

    made, cleanup = {}, []
    voice = None
    try:
        for model, design in DESIGNED.items():
            if model in only:
                made[model] = make({"text": SENTENCE, "mode": "design", "model": model, "instruct": design})
        if PRESET["model"] in only:
            made[PRESET["model"]] = make({"text": SENTENCE, "mode": "preset", **PRESET})
        if set(CLONED) & set(only):
            print("參考錄音（聲音描述的成品，拿來仿）")
            ref = make({"text": REFERENCE, "mode": "design", "model": REFERENCE_MODEL, "instruct": DESIGN})
            cleanup.append(ref)
            voice = call("POST", f"/api/history/{ref['id']}/voice", {"label": "官網試聽的參考聲音"})["name"]
            for model in CLONED:
                if model in only:
                    made[model] = make({"text": SENTENCE, "mode": "clone", "model": model, "voice": voice})

        OUT.mkdir(parents=True, exist_ok=True)
        for model, job in made.items():
            target = OUT / f"{model}.m4a"
            subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "64000", "-c", "1",
                            job["path"], str(target)], check=True)
            print(f"  {target.relative_to(OUT.parent.parent)}：{target.stat().st_size // 1024} KB")
    finally:
        for job in [*made.values(), *cleanup]:
            call("DELETE", f"/api/history/{job['id']}")
        if voice:
            call("DELETE", f"/api/voices/{voice}")


if __name__ == "__main__":
    main()
