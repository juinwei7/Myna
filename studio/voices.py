"""聲音庫：仿聲用的參考錄音。

一個聲音＝`voices/<名稱>.wav`（24 kHz 單聲道）＋`.txt`（逐字稿）＋`.json`（顯示名稱等）。
聲音跟模型無關，任何支援仿聲的模型都能用。
刪除時 app 會先把檔案丟進垃圾桶（才能從 Finder 救回、能 ⌘Z），這裡的刪除對已不存在的檔案不報錯。
"""
import json
import re
import subprocess
import wave
from datetime import datetime
from pathlib import Path

from . import config

SHORT_SECONDS = 3.0
LONG_SECONDS = 30.0


def _paths(name):
    return (config.VOICES / f"{name}.wav", config.VOICES / f"{name}.txt", config.VOICES / f"{name}.json")


def _meta(name):
    try:
        return json.loads(_paths(name)[2].read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def duration(path):
    try:
        with wave.open(str(path)) as w:
            return w.getnframes() / w.getframerate()
    except (wave.Error, OSError, EOFError):
        return 0.0


def to_wav(src, dst):
    """任何音檔 → 24 kHz 單聲道 wav。"""
    if config.FFMPEG:
        cmd = [config.FFMPEG, "-loglevel", "error", "-y", "-i", str(src), "-ac", "1", "-ar", "24000", str(dst)]
    else:
        cmd = ["/usr/bin/afconvert", "-f", "WAVE", "-d", "LEI16@24000", "-c", "1", str(src), str(dst)]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise ValueError(f"讀不了這個音檔：{(result.stderr or '').strip()[:200]}")


def safe_name(name):
    name = re.sub(r"[^\w\-]", "", (name or "").strip(), flags=re.UNICODE)
    if not name:
        raise ValueError("聲音代號只能用中英文、數字、底線、連字號")
    return name


def quality(seconds):
    if seconds < SHORT_SECONDS:
        return "short"
    if seconds > LONG_SECONDS:
        return "long"
    return "good"


def view(name):
    wav, txt, _ = _paths(name)
    meta = _meta(name)
    seconds = round(duration(wav), 1)
    created = meta.get("created") or datetime.fromtimestamp(wav.stat().st_mtime).isoformat(timespec="seconds")
    return {
        "id": f"clone:{name}",
        "name": name,
        "label": meta.get("label") or name,
        "kind": "clone",
        "note": meta.get("note", "仿聲：照參考錄音的音色與口音"),
        "transcript": txt.read_text(encoding="utf-8").strip(),
        "seconds": seconds,
        "quality": quality(seconds),
        "created": created,
        "path": str(wav),
    }


def list_voices():
    config.ensure_dirs()
    return [view(wav.stem) for wav in sorted(config.VOICES.glob("*.wav"))
            if (config.VOICES / f"{wav.stem}.txt").exists()]


def get(name):
    wav, txt, _ = _paths(safe_name(name))
    if not wav.exists() or not txt.exists():
        raise ValueError(f"沒有這個聲音：{name}")
    return view(wav.stem)


def _write_meta(name, label, extra=None):
    meta = {**_meta(name), "label": label or name, **(extra or {})}
    meta.setdefault("created", datetime.now().isoformat(timespec="seconds"))
    _paths(name)[2].write_text(json.dumps(meta, ensure_ascii=False), encoding="utf-8")


def add(name, audio_path, transcript, label=None, extra=None):
    config.ensure_dirs()
    name = safe_name(name)
    transcript = (transcript or "").strip()
    if not transcript:
        raise ValueError("要附上參考錄音一字不差的逐字稿")
    src = Path(audio_path).expanduser()
    if not src.exists():
        raise ValueError(f"找不到音檔：{src}")
    wav, txt, _ = _paths(name)
    to_wav(src, wav)
    txt.write_text(transcript + "\n", encoding="utf-8")
    _write_meta(name, label, extra)
    return view(name)


def update(name, label=None, transcript=None):
    current = get(name)
    if transcript is not None:
        transcript = transcript.strip()
        if not transcript:
            raise ValueError("逐字稿不可以是空的")
        _paths(current["name"])[1].write_text(transcript + "\n", encoding="utf-8")
    if label is not None:
        _write_meta(current["name"], label.strip() or current["name"])
    return view(current["name"])


def delete(name):
    for p in _paths(safe_name(name)):
        p.unlink(missing_ok=True)


def unique_name(base):
    base = safe_name(base)
    name, n = base, 2
    while _paths(name)[0].exists():
        name, n = f"{base}-{n}", n + 1
    return name
