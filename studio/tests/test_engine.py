"""驗收 D3～D7：產生流程、佇列、取消、紀錄；E5、E6：記憶體上限。"""
import json
import threading
import time
import unittest

from studio import catalog, config, history, settings, text
from studio.engine import Engine, FakeModel
from studio.jobs import Jobs
from studio.resolve import resolve, resolve_batch
from studio.tests import helpers


def wait(job, timeout=10):
    deadline = time.time() + timeout
    while job.active and time.time() < deadline:
        time.sleep(0.01)
    return job


class SlowLoader:
    """載入時卡住，讓測試能在排隊／產生途中動手。"""

    def __init__(self):
        self.gate = threading.Event()

    def __call__(self, spec):
        model = FakeModel(spec)
        original = model.generate

        def generate(text, **kw):
            self.gate.wait(5)
            yield from original(text, **kw)
        model.generate = generate
        return model


class EngineTests(unittest.TestCase):
    def setUp(self):
        helpers.reset()
        helpers.add_voice()
        helpers.mark_downloaded(*[m.id for m in catalog.CATALOG])
        text.save_rules([("山嵐", "山藍")])
        FakeModel.calls.clear()

    def test_d2_pronounce_and_record_fields(self):
        jobs = Jobs(Engine())
        job = wait(jobs.submit([resolve({"text": "歡迎來到山嵐", "voice": "clone:tw-female"})])[0])
        self.assertEqual(job.status, "done", job.error)
        self.assertEqual(FakeModel.calls[0]["text"], "歡迎來到山藍")
        rec = job.result
        self.assertEqual((rec["text"], rec["spoken"]), ("歡迎來到山嵐", "歡迎來到山藍"))
        for key in ("model", "model_name", "mode", "spoken", "file", "seconds"):  # D6
            self.assertIn(key, rec)
        self.assertEqual(rec["model"], "qwen3-1.7b-base")
        self.assertTrue((config.OUT / rec["file"]).exists())

    def test_d3_progress_by_segments(self):
        seen = []
        engine = Engine()
        r = resolve({"text": "一\n二\n三\n四\n五", "voice": "clone:tw-female"})
        engine.synth(r, lambda f, s: seen.append((f, s)))
        fractions = [f for f, _ in seen]
        self.assertEqual(fractions, sorted(fractions))
        self.assertEqual(fractions[-1], 1.0)
        self.assertTrue(any("3／5" in s for _, s in seen))
        self.assertEqual(len(FakeModel.calls), 5)

    def test_d4_cancel_queued(self):
        loader = SlowLoader()
        jobs = Jobs(Engine(loader))
        r1 = resolve({"text": "第一筆", "voice": "clone:tw-female"})
        r2 = resolve({"text": "第二筆", "voice": "clone:tw-female"})
        first, second = jobs.submit([r1])[0], jobs.submit([r2])[0]
        jobs.cancel(second.id)
        loader.gate.set()
        wait(first), wait(second)
        self.assertEqual((first.status, second.status), ("done", "cancelled"))
        self.assertEqual(len(history.read()), 1)

    def test_d5_cancel_running_between_segments(self):
        loader = SlowLoader()
        jobs = Jobs(Engine(loader))
        job = jobs.submit([resolve({"text": "一\n二\n三", "voice": "clone:tw-female"})])[0]
        while job.status != "running":
            time.sleep(0.01)
        jobs.cancel(job.id)
        loader.gate.set()
        wait(job)
        self.assertEqual(job.status, "cancelled")
        self.assertEqual(history.read(), [])
        self.assertEqual(list(config.OUT.glob("*.wav")), [])

    def test_batch(self):
        jobs = Jobs(Engine())
        created = jobs.submit(resolve_batch({"text": "比較", "voice": "clone:tw-female",
                                             "models": ["voxcpm2", "omnivoice", "breeze-tts-2"]}))
        for j in created:
            wait(j)
        self.assertEqual({j.status for j in created}, {"done"})
        self.assertEqual(len({j.batch for j in created}), 1)
        self.assertEqual([j.result["model"] for j in created], ["voxcpm2", "omnivoice", "breeze-tts-2"])
        self.assertEqual({r["batch"] for r in history.read()}, {created[0].batch})

    def test_omnivoice_speed_skips_ffmpeg(self):
        engine = Engine()
        rec = engine.synth(resolve({"text": "你好", "voice": "clone:tw-female", "model": "omnivoice",
                                    "speed": 1.5}))
        self.assertIn("duration_s", FakeModel.calls[-1])
        self.assertEqual(rec["speed"], 1.5)

    def test_error_reported(self):
        def broken(spec):
            raise RuntimeError("權重壞了")
        jobs = Jobs(Engine(broken))
        job = wait(jobs.submit([resolve({"text": "你好", "voice": "clone:tw-female"})])[0])
        self.assertEqual((job.status, job.error), ("error", "權重壞了"))

    def test_d7_legacy_record(self):
        config.OUT.mkdir(parents=True, exist_ok=True)
        helpers.write_tone(config.OUT / "old.wav", 1)
        old = {"id": "old", "created": "2026-11-17T10:00:00", "text": "舊的", "voice": "preset:Vivian",
               "voice_label": "Vivian", "instruct": "", "speed": 1.0, "file": "old.wav", "seconds": 1.0}
        config.HISTORY.write_text(json.dumps(old, ensure_ascii=False) + "\n", encoding="utf-8")
        rec = history.read()[0]
        self.assertEqual((rec["mode"], rec["model"], rec["model_name"]),
                         ("preset", "qwen3-1.7b-custom", "Qwen3-TTS 1.7B 配音員"))

    def test_restore(self):
        engine = Engine()
        rec = engine.synth(resolve({"text": "要刪的", "voice": "clone:tw-female"}))
        rows = config.HISTORY.read_text(encoding="utf-8")
        history.delete(rec["id"])
        self.assertEqual(history.read(), [])
        helpers.write_tone(config.OUT / rec["file"], 1)  # app 從垃圾桶搬回來
        history.restore(rec)
        self.assertEqual([r["id"] for r in history.read()], [rec["id"]])
        with self.assertRaises(ValueError):
            history.restore({**rec, "file": "../voices/tw-female.wav"})
        self.assertTrue(rows)


class MemoryTests(unittest.TestCase):
    def setUp(self):
        helpers.reset()

    def test_e5_evicts_least_recently_used(self):
        settings.update({"memory_budget_gb": 11})  # 4.5×1.2＝5.4 GB，只放得下兩個
        engine = Engine()
        a, b, c = (settings.find(i) for i in ("qwen3-1.7b-base", "qwen3-1.7b-custom", "qwen3-1.7b-design"))
        engine.get(a), engine.get(b), engine.get(a), engine.get(c)
        self.assertEqual(engine.loaded_ids(), ["qwen3-1.7b-base", "qwen3-1.7b-design"])

    def test_e6_single_model_over_budget(self):
        settings.update({"memory_budget_gb": 4})
        engine = Engine()
        engine.get(settings.find("breeze-tts-2"))
        self.assertEqual(engine.loaded_ids(), ["breeze-tts-2"])
        engine.get(settings.find("omnivoice"))
        self.assertEqual(engine.loaded_ids(), ["omnivoice"])


if __name__ == "__main__":
    unittest.main()
