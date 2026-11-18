"""驗收 E1～E4：模型檔案的生命週期（假下載程式＋臨時快取）。"""
import os
import time
import unittest

from studio import models, settings
from studio.tests import fake_downloader, helpers


class ModelFileTests(unittest.TestCase):
    def setUp(self):
        helpers.reset()
        os.environ.pop("FAKE_DL_FAIL", None)
        os.environ.pop("FAKE_DL_DELAY", None)

    def test_e1_downloaded_detection(self):
        qwen = settings.find("qwen3-1.7b-base")
        self.assertFalse(models.is_downloaded(qwen))
        fake_downloader.make_repo(qwen.repo, partial=True)
        self.assertFalse(models.is_downloaded(qwen))
        fake_downloader.make_repo(qwen.repo)
        for p in (models.repo_dir(qwen.repo) / "blobs").glob("*.incomplete"):
            p.unlink()
        self.assertTrue(models.is_downloaded(qwen))
        moss = settings.find("moss-tts-nano")
        fake_downloader.make_repo(moss.repo)
        self.assertFalse(models.is_downloaded(moss), "附屬模型沒下載不算完整")
        fake_downloader.make_repo(moss.extra_repos[0])
        self.assertTrue(models.is_downloaded(moss))

    def test_e2_download_progress(self):
        os.environ["FAKE_DL_DELAY"] = "0.03"
        spec = settings.find("omnivoice")
        models.start(spec)
        seen = []
        while True:
            v = models.download_view(spec)
            if v["state"] != "downloading":
                break
            if v["progress"] is not None:
                seen.append(v["progress"])
            time.sleep(0.02)
        self.assertEqual(models.download_view(spec)["state"], "downloaded")
        self.assertTrue(seen and all(0 <= p < 1 for p in seen))
        self.assertEqual(seen, sorted(seen))
        self.assertGreater(len(set(seen)), 2)

    def test_e3_cancel(self):
        os.environ["FAKE_DL_DELAY"] = "0.2"
        spec = settings.find("voxcpm2")
        dl = models.start(spec)
        time.sleep(0.3)
        models.cancel(spec.id)
        self.assertIsNotNone(dl.proc.poll())
        self.assertEqual(models.download_view(spec)["state"], "available")

    def test_download_failure_message(self):
        os.environ["FAKE_DL_FAIL"] = "1"
        spec = settings.find("voxcpm2")
        models.start(spec)
        models.wait(spec.id, 10)
        v = models.download_view(spec)
        self.assertEqual(v["state"], "available")
        self.assertIn("連不上 Hugging Face", v["error"])

    def test_e4_delete_keeps_shared_and_others(self):
        helpers.mark_downloaded("moss-tts-nano", "omnivoice")
        moss, omni = settings.find("moss-tts-nano"), settings.find("omnivoice")
        tokenizer = moss.extra_repos[0]
        models.delete(moss, keep_repos={tokenizer})
        self.assertFalse(models.repo_dir(moss.repo).exists())
        self.assertTrue(models.repo_dir(tokenizer).exists())
        self.assertTrue(models.is_downloaded(omni))
        models.delete(omni)
        self.assertFalse(models.repo_dir(omni.repo).exists())


if __name__ == "__main__":
    unittest.main()
