"""模型的載入／卸載，以及從文字到音檔的產生流程。

只會在工作執行緒裡被呼叫（憲法 A4）；`_lock` 防的是 API 執行緒同時查詢載入狀態。
"""
import gc
import subprocess
import threading
import uuid
import wave
from collections import OrderedDict
from datetime import datetime

import numpy as np

from . import adapters, config, history, settings, text

MEMORY_FACTOR = 1.2  # 權重以外還有暫存，估計用量抓檔案大小的 1.2 倍


class Cancelled(Exception):
    pass


def _real_loader(spec):
    from mlx_audio.tts.utils import load_model
    return load_model(spec.repo)


class FakeModel:
    """測試用：依文字長度產生正弦波，並記下收到的參數。"""
    calls = []

    def __init__(self, spec):
        self.spec = spec
        self.sample_rate = spec.sample_rate

    def generate(self, text, **kwargs):
        FakeModel.calls.append({"model": self.spec.id, "text": text, **kwargs})
        n = int(self.sample_rate * 0.02 * max(1, len(text)))
        t = np.arange(n) / self.sample_rate

        class Result:
            audio = (0.2 * np.sin(2 * np.pi * 220 * t)).astype(np.float32)
        yield Result()


def _fake_loader(spec):
    return FakeModel(spec)


class Engine:
    def __init__(self, loader=None):
        self._loader = loader or (_fake_loader if config.FAKE_ENGINE else _real_loader)
        self._models = OrderedDict()
        self._lock = threading.RLock()
        self._ref_cache = {}
        self.loading = None

    # ---------- 記憶體 ----------

    def loaded_ids(self):
        with self._lock:
            return list(self._models)

    @staticmethod
    def estimate_gb(spec):
        return spec.size_gb * MEMORY_FACTOR

    def _used_gb(self):
        return sum(self.estimate_gb(spec) for spec in map(settings.find, self._models) if spec)

    def get(self, spec):
        with self._lock:
            if spec.id in self._models:
                self._models.move_to_end(spec.id)
                return self._models[spec.id]
            budget = settings.memory_budget_gb()
            # 從最久沒用的開始卸載，直到放得下；正要載入的這個超過上限也照樣載入
            while self._models and self._used_gb() + self.estimate_gb(spec) > budget:
                self._evict(next(iter(self._models)))
            self.loading = spec.id
        try:
            model = self._loader(spec)
        finally:
            self.loading = None
        with self._lock:
            self._models[spec.id] = model
        return model

    def _evict(self, model_id):
        self._models.pop(model_id, None)
        gc.collect()
        if not config.FAKE_ENGINE:
            import mlx.core as mx
            mx.clear_cache()

    def unload(self, model_id):
        with self._lock:
            self._evict(model_id)

    # ---------- 產生 ----------

    def _ref_audio(self, path, sample_rate):
        import os
        key = (path, sample_rate, os.path.getmtime(path))
        if key not in self._ref_cache:
            from mlx_audio.utils import load_audio
            self._ref_cache = {k: v for k, v in self._ref_cache.items() if k[0] != path}
            self._ref_cache[key] = load_audio(path, sample_rate=sample_rate)
        return self._ref_cache[key]

    def synth(self, r, on_progress=lambda fraction, stage: None, cancelled=lambda: False):
        spoken = text.apply_pronounce(r.text)
        segs = text.segments(spoken)
        if not segs:
            raise ValueError("文字不可以是空的")

        on_progress(0.0, f"載入 {r.spec.name}…")
        model = self.get(r.spec)
        sr = model.sample_rate
        ref_audio = self._ref_audio(r.ref_path, sr) if r.mode == "clone" else None

        pieces = []
        for i, seg in enumerate(segs):
            if cancelled():
                raise Cancelled()
            on_progress(i / len(segs), f"產生中 {i + 1}／{len(segs)} 段" if len(segs) > 1 else "產生中…")
            kwargs = adapters.build(r.spec, r, seg.text, ref_audio)
            results = list(model.generate(text=seg.text, **kwargs))
            if not results:
                raise RuntimeError(f"{r.spec.name} 沒有產出聲音（第 {i + 1} 段）")
            pieces.extend(np.array(x.audio).astype(np.float32).reshape(-1) for x in results)
            if seg.pause_after:
                pieces.append(np.zeros(int(sr * seg.pause_after), dtype=np.float32))
        if cancelled():
            raise Cancelled()
        audio = np.concatenate(pieces)

        on_progress(1.0, "存檔中…")
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        tag = f"{r.spec.id}-{r.voice.replace(':', '-')}".replace("/", "-")
        path = config.OUT / f"{stamp}-{tag}-{uuid.uuid4().hex[:4]}.wav"
        _write_wav(path, audio, sr)
        if abs(r.speed - 1.0) > 0.01 and not r.spec.native_speed:
            _change_speed(path, r.speed)

        record = {
            "id": path.stem,
            "created": datetime.now().isoformat(timespec="seconds"),
            "text": r.text,
            "spoken": spoken,
            "mode": r.mode,
            "model": r.spec.id,
            "model_name": r.spec.name,
            "voice": r.voice,
            "voice_label": r.voice_label,
            "instruct": r.instruct,
            "speed": r.speed,
            "file": path.name,
            "seconds": round(_duration(path), 1),
            "segments": len(segs),
            "batch": r.batch,
        }
        history.append(record)
        return history.get(record["id"])


def _write_wav(path, audio, sample_rate):
    pcm = (np.clip(audio, -1.0, 1.0) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sample_rate)
        w.writeframes(pcm.tobytes())


def _duration(path):
    try:
        with wave.open(str(path)) as w:
            return w.getnframes() / w.getframerate()
    except (wave.Error, OSError):
        return 0.0


def _change_speed(path, speed):
    if not config.FFMPEG:
        path.unlink(missing_ok=True)
        raise ValueError("這個模型調語速需要 ffmpeg（brew install ffmpeg），或把語速設回 1.0、改用 OmniVoice")
    tmp = path.with_suffix(".tmp.wav")
    subprocess.run([config.FFMPEG, "-loglevel", "error", "-y", "-i", str(path),
                    "-af", f"atempo={max(0.5, min(2.0, speed))}", str(tmp)], check=True)
    tmp.replace(path)
