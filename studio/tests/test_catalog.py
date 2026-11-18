"""驗收 A：目錄與能力。"""
import unittest

from studio import adapters, catalog


class CatalogTests(unittest.TestCase):
    def test_a1_complete_and_unique(self):
        ids = [m.id for m in catalog.CATALOG]
        self.assertEqual(len(ids), 8)
        self.assertEqual(len(set(ids)), len(ids))
        for m in catalog.CATALOG:
            self.assertIn(m.family, adapters.ADAPTERS, m.id)

    def test_a2_capabilities_consistent(self):
        for m in catalog.CATALOG:
            self.assertTrue(set(m.modes) <= set(catalog.MODES), m.id)
            self.assertEqual(bool(m.presets), m.supports("preset"), m.id)
            self.assertTrue(set(m.instruct_modes) <= set(m.modes), m.id)
            self.assertIn(m.clone_text, ("required", "optional"))
        for mode, model_id in catalog.DEFAULTS.items():
            self.assertTrue(catalog.builtin(model_id).supports(mode))

    def test_a3_license(self):
        for m in catalog.CATALOG:
            self.assertTrue(m.license, m.id)
        self.assertFalse(catalog.builtin("breeze-tts-2").commercial)
        self.assertTrue(catalog.builtin("qwen3-1.7b-base").commercial)

    def test_a4_infer_custom(self):
        cfg = {"model_type": "qwen3_tts", "tts_model_type": "custom_voice",
               "talker_config": {"spk_id": {"vivian": 1, "uncle_fu": 2}}}
        spec = catalog.infer_custom("mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit", cfg, 1.2)
        self.assertEqual(spec.modes, ("preset",))
        self.assertEqual([p.id for p in spec.presets], ["vivian", "uncle_fu"])
        self.assertTrue(spec.custom)
        self.assertEqual(catalog.infer_custom("a/b", {"model_type": "voxcpm2"}, 1).modes, ("clone", "design"))
        with self.assertRaises(ValueError):
            catalog.infer_custom("a/b", {"model_type": "kokoro"}, 1)

    def test_round_trip(self):
        for m in catalog.CATALOG:
            self.assertEqual(catalog.spec_from_dict(m.to_dict()), m)


if __name__ == "__main__":
    unittest.main()
