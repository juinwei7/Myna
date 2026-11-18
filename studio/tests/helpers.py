"""測試小工具：清空臨時資料夾、做一個假的參考聲音、把模型標成已下載。"""
import math
import shutil
import struct
import wave

from studio import config, models, settings
from studio.tests import fake_downloader


def reset():
    # 防呆：只准清測試建立的臨時資料夾，絕不碰正式資料
    assert "voice-studio-test-" in str(config.ROOT) and "voice-studio-test-" in str(models.cache_dir())
    for d in (config.ROOT, models.cache_dir()):
        shutil.rmtree(d, ignore_errors=True)
        d.mkdir(parents=True, exist_ok=True)
    config.ensure_dirs()
    models._downloads.clear()


def write_tone(path, seconds=6.0, rate=24000):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        frames = b"".join(struct.pack("<h", int(8000 * math.sin(2 * math.pi * 220 * i / rate)))
                          for i in range(int(seconds * rate)))
        w.writeframes(frames)


def add_voice(name="tw-female", label="台灣女聲", transcript="在密碼學中，加密是將明文資訊改變為難以讀取的密文內容。"):
    write_tone(config.VOICES / f"{name}.wav")
    (config.VOICES / f"{name}.txt").write_text(transcript + "\n", encoding="utf-8")
    (config.VOICES / f"{name}.json").write_text('{"label": "%s"}' % label, encoding="utf-8")


def mark_downloaded(*model_ids):
    for model_id in model_ids:
        spec = settings.find(model_id)
        for repo in models.repos_of(spec):
            fake_downloader.make_repo(repo)
