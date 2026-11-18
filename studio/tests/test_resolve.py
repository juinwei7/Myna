"""驗收 B：請求解析與相容；驗收 C：轉接器。"""
import unittest

from studio import adapters, catalog, settings
from studio.resolve import resolve, resolve_batch
from studio.tests import helpers

ALL = [m.id for m in catalog.CATALOG]


class ResolveTests(unittest.TestCase):
    def setUp(self):
        helpers.reset()
        helpers.add_voice()
        helpers.mark_downloaded(*ALL)

    def test_b1_legacy_clone(self):
        r = resolve({"text": "你好", "voice": "clone:tw-female"})
        self.assertEqual((r.mode, r.spec.id, r.voice_label), ("clone", "qwen3-1.7b-base", "台灣女聲"))
        self.assertTrue(r.ref_text.startswith("在密碼學中"))

    def test_b2_legacy_preset(self):
        r = resolve({"text": "你好", "voice": "preset:Vivian"})
        self.assertEqual((r.mode, r.spec.id, r.speaker.id), ("preset", "qwen3-1.7b-custom", "Vivian"))

    def test_b3_legacy_design(self):
        r = resolve({"text": "你好", "voice": "design", "instruct": "溫暖的女聲"})
        self.assertEqual((r.mode, r.spec.id, r.instruct), ("design", "qwen3-1.7b-design", "溫暖的女聲"))
        with self.assertRaisesRegex(ValueError, "聲音描述"):
            resolve({"text": "你好", "voice": "design"})

    def test_b4_explicit_model(self):
        r = resolve({"text": "你好", "mode": "clone", "voice": "tw-female", "model": "voxcpm2"})
        self.assertEqual(r.spec.id, "voxcpm2")

    def test_b5_unsupported_mode(self):
        with self.assertRaisesRegex(ValueError, "不支援配音員"):
            resolve({"text": "你好", "mode": "preset", "speaker": "Vivian", "model": "voxcpm2"})

    def test_b6_not_downloaded(self):
        helpers.reset()
        helpers.add_voice()
        with self.assertRaisesRegex(ValueError, "還沒下載"):
            resolve({"text": "你好", "voice": "clone:tw-female"})

    def test_b7_batch_all_or_nothing(self):
        rs = resolve_batch({"text": "你好", "voice": "clone:tw-female", "models": ["voxcpm2", "omnivoice"]})
        self.assertEqual([r.spec.id for r in rs], ["voxcpm2", "omnivoice"])
        with self.assertRaises(ValueError):
            resolve_batch({"text": "你好", "voice": "clone:tw-female",
                           "models": ["voxcpm2", "qwen3-1.7b-design"]})

    def test_b8_instruct_only_when_supported(self):
        r = resolve({"text": "你好", "voice": "clone:tw-female", "instruct": "慢一點"})
        self.assertEqual(r.instruct, "")
        r = resolve({"text": "你好", "voice": "clone:tw-female", "instruct": "慢一點", "model": "breeze-tts-2"})
        self.assertEqual(r.instruct, "慢一點")

    def test_defaults_follow_settings(self):
        settings.update({"defaults": {"clone": "omnivoice"}})
        self.assertEqual(resolve({"text": "你好", "voice": "clone:tw-female"}).spec.id, "omnivoice")
        with self.assertRaises(ValueError):
            settings.update({"defaults": {"preset": "omnivoice"}})

    def test_default_voice_is_first_in_library(self):
        r = resolve({"text": "你好"})
        self.assertEqual((r.mode, r.voice), ("clone", "clone:tw-female"))
        helpers.add_voice("zz-second", "第二個聲音")
        settings.update({"default_voice": "zz-second"})
        self.assertEqual(resolve({"text": "你好"}).voice, "clone:zz-second", "有設定預設聲音就用它")
        with self.assertRaises(ValueError):
            settings.update({"default_voice": "nobody"})
        settings.update({"default_voice": ""})
        self.assertEqual(resolve({"text": "你好"}).voice, "clone:tw-female")
        helpers.reset()
        helpers.mark_downloaded(*ALL)
        with self.assertRaisesRegex(ValueError, "聲音庫還是空的"):
            resolve({"text": "你好"})

    def test_errors(self):
        with self.assertRaisesRegex(ValueError, "空的"):
            resolve({"text": "  ", "voice": "clone:tw-female"})
        with self.assertRaisesRegex(ValueError, "沒有這個聲音"):
            resolve({"text": "你好", "voice": "clone:nobody"})
        with self.assertRaisesRegex(ValueError, "配音員"):
            resolve({"text": "你好", "voice": "preset:Nobody"})


class AdapterTests(unittest.TestCase):
    def setUp(self):
        helpers.reset()
        helpers.add_voice()
        helpers.mark_downloaded(*ALL)

    def kw(self, payload, segment="歡迎使用語音工作室"):
        r = resolve({"text": segment, **payload})
        return adapters.build(r.spec, r, segment, "REF")

    def test_c1_qwen_clone(self):
        kw = self.kw({"voice": "clone:tw-female"})
        self.assertEqual(kw["ref_audio"], "REF")
        self.assertTrue(kw["ref_text"])
        self.assertEqual(kw["lang_code"], "chinese")

    def test_c2_qwen_preset(self):
        kw = self.kw({"voice": "preset:Serena", "instruct": "熱情"})
        self.assertEqual((kw["voice"], kw["instruct"]), ("Serena", "熱情"))
        self.assertNotIn("ref_audio", kw)

    def test_c3_breeze_instruct(self):
        kw = self.kw({"voice": "clone:tw-female", "model": "breeze-tts-2", "instruct": "慢一點"})
        self.assertEqual((kw["instruct"], kw["cfg_scale"]), ("慢一點", 4))
        kw = self.kw({"voice": "clone:tw-female", "model": "breeze-tts-2"})
        self.assertNotIn("cfg_scale", kw)

    def test_c4_omnivoice_native_speed(self):
        natural = adapters.natural_seconds("歡迎使用語音工作室")
        kw = self.kw({"voice": "clone:tw-female", "model": "omnivoice", "speed": 1.25})
        self.assertAlmostEqual(kw["duration_s"], natural / 1.25, places=1)
        self.assertNotIn("duration_s", self.kw({"voice": "clone:tw-female", "model": "omnivoice"}))

    def test_c5_moss(self):
        kw = self.kw({"voice": "clone:tw-female", "model": "moss-tts-nano"})
        self.assertEqual((kw["ref_audio"], kw["mode"]), ("REF", "voice_clone"))

    def test_design_families(self):
        for model_id in ("voxcpm2", "omnivoice", "breeze-tts-2"):
            kw = self.kw({"voice": "design", "model": model_id, "instruct": "溫暖的女聲"})
            self.assertEqual(kw["instruct"], "溫暖的女聲", model_id)
            self.assertNotIn("ref_audio", kw)


if __name__ == "__main__":
    unittest.main()
