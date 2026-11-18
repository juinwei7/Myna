"""Spec 003 驗收 A：分段成品（邊產生邊播用）。"""
import threading
import time
import unittest
import wave

from studio import catalog, config
from studio.engine import Engine, FakeModel
from studio.jobs import Jobs
from studio.resolve import resolve
from studio.tests import helpers
from studio.tests.test_engine import wait


def frames(path):
    with wave.open(str(path)) as w:
        return w.getnframes()


class WatchingLoader:
    """每次模型被叫去產生一段時，記下當時已經存好幾段。"""

    def __init__(self):
        self.job = None
        self.seen = []

    def __call__(self, spec):
        model = FakeModel(spec)
        original = model.generate

        def generate(text, **kw):
            self.seen.append((self.job.parts, sorted(p.name for p in self.job.parts_dir.glob("*.wav"))
                              if self.job.parts_dir.exists() else []))
            yield from original(text, **kw)
        model.generate = generate
        return model


class PartsTests(unittest.TestCase):
    def setUp(self):
        helpers.reset()
        helpers.add_voice()
        helpers.mark_downloaded(*[m.id for m in catalog.CATALOG])
        FakeModel.calls.clear()

    def run_job(self, jobs, payload, **kw):
        return jobs.submit([resolve(payload)], **kw)[0]

    def test_a1_a2_a7_parts_grow_and_add_up(self):
        loader = WatchingLoader()
        jobs = Jobs(Engine(loader))
        job = self.run_job(jobs, {"text": "第一段\n第二段比較長一點\n第三段", "voice": "clone:tw-female"})
        loader.job = job
        wait(job)
        self.assertEqual(job.status, "done", job.error)
        # 產生第 n 段的時候，前面 n-1 段已經存好了
        self.assertEqual([n for n, _ in loader.seen], [0, 1, 2])
        self.assertEqual(loader.seen[2][1], ["0001.wav", "0002.wav"])
        view = job.view()
        self.assertEqual((view["parts"], view["segments"], view["speak"]), (3, 3, False))
        self.assertEqual(view["parts_dir"], str(config.PARTS / job.id))
        for key in ("job_id", "kind", "status", "progress", "stage", "batch", "model", "queued_at", "file"):
            self.assertIn(key, view)
        parts = [job.part_path(i) for i in range(3)]
        self.assertEqual(sum(frames(p) for p in parts), frames(config.OUT / view["file"]))
        self.assertEqual(list(job.parts_dir.glob("*.tmp")), [])

    def test_a3_single_segment_has_no_parts(self):
        jobs = Jobs(Engine())
        job = wait(self.run_job(jobs, {"text": "只有一段", "voice": "clone:tw-female"}))
        view = job.view()
        self.assertEqual((job.status, view["parts"], view["parts_dir"]), ("done", 0, None))
        self.assertFalse(job.parts_dir.exists())

    @unittest.skipUnless(config.FFMPEG, "需要 ffmpeg")
    def test_a4_speed_applied_per_part(self):
        jobs = Jobs(Engine())
        text = "這一段有十個字左右喔\n這一段也有十個字左右"
        normal = wait(self.run_job(jobs, {"text": text, "voice": "clone:tw-female"}))
        fast = wait(self.run_job(jobs, {"text": text, "voice": "clone:tw-female", "speed": 2.0}))
        self.assertEqual((normal.status, fast.status), ("done", "done"), fast.error)
        ratio = frames(fast.part_path(0)) / frames(normal.part_path(0))
        self.assertAlmostEqual(ratio, 0.5, delta=0.1)
        self.assertEqual(sum(frames(fast.part_path(i)) for i in range(2)),
                         frames(config.OUT / fast.result["file"]))

    def test_a4_missing_ffmpeg_fails_before_generating(self):
        original, config.FFMPEG = config.FFMPEG, None
        self.addCleanup(setattr, config, "FFMPEG", original)
        jobs = Jobs(Engine())
        job = wait(self.run_job(jobs, {"text": "一\n二", "voice": "clone:tw-female", "speed": 1.5}))
        self.assertEqual(job.status, "error")
        self.assertIn("ffmpeg", job.error)
        self.assertEqual(FakeModel.calls, [])

    def test_a5_cancel_removes_parts(self):
        gate, calls = threading.Event(), []

        def loader(spec):
            model = FakeModel(spec)
            original = model.generate

            def generate(text, **kw):
                calls.append(text)
                if len(calls) > 1:  # 第一段照常做，第二段開始卡住，讓測試有時間取消
                    gate.wait(5)
                yield from original(text, **kw)
            model.generate = generate
            return model

        jobs = Jobs(Engine(loader))
        job = self.run_job(jobs, {"text": "一\n二\n三\n四", "voice": "clone:tw-female"})
        while job.parts < 1 and job.active:
            time.sleep(0.005)
        self.assertTrue(job.part_path(0).exists())
        jobs.cancel(job.id)
        gate.set()
        wait(job)
        self.assertEqual(job.status, "cancelled")
        self.assertEqual(job.view()["parts"], 0)
        self.assertFalse(job.parts_dir.exists())

    def test_a6_sweep_old_and_startup(self):
        jobs = Jobs(Engine())
        old = wait(self.run_job(jobs, {"text": "一\n二", "voice": "clone:tw-female"}))
        stray = config.PARTS / "feedfacecafe"
        stray.mkdir(parents=True)
        self.assertTrue(old.parts_dir.exists())
        old.finished -= config.PARTS_KEEP_SECONDS + 1
        recent = wait(self.run_job(jobs, {"text": "三\n四", "voice": "clone:tw-female"}))
        wait(self.run_job(jobs, {"text": "五", "voice": "clone:tw-female"}))
        self.assertFalse(old.parts_dir.exists())
        self.assertFalse(stray.exists())
        self.assertTrue(recent.parts_dir.exists())
        Jobs(Engine())  # 服務重新啟動
        self.assertFalse(config.PARTS.exists() and any(config.PARTS.iterdir()))

    def test_speak_flag(self):
        jobs = Jobs(Engine())
        job = wait(self.run_job(jobs, {"text": "做完了", "voice": "clone:tw-female"}, speak=True))
        self.assertTrue(job.view()["speak"])
        self.assertEqual(job.status, "done")


if __name__ == "__main__":
    unittest.main()
