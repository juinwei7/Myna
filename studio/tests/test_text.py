"""驗收 D1、D2：分段與發音字典。"""
import unittest

from studio import config, text
from studio.tests import helpers


class SegmentTests(unittest.TestCase):
    def test_d1_lines_and_paragraphs(self):
        segs = text.segments("第一行\n第二行\n\n第二段")
        self.assertEqual([s.text for s in segs], ["第一行", "第二行", "第二段"])
        self.assertEqual([s.pause_after for s in segs], [text.PAUSE_LINE, text.PAUSE_PARAGRAPH, 0.0])

    def test_d1_long_line_split_on_sentences(self):
        line = "這是一句很長的話。" * 12
        segs = text.segments(line)
        self.assertGreater(len(segs), 1)
        self.assertTrue(all(len(s.text) <= text.LONG_SENTENCE for s in segs))
        self.assertEqual(segs[0].pause_after, text.PAUSE_SENTENCE)
        self.assertEqual("".join(s.text for s in segs), line)

    def test_d1_no_punctuation_hard_split(self):
        segs = text.segments("啊" * 300)
        self.assertTrue(all(len(s.text) <= text.LONG_SENTENCE for s in segs))
        self.assertEqual(sum(len(s.text) for s in segs), 300)

    def test_lang(self):
        self.assertEqual(text.detect_lang("Hello 世界"), "zh")
        self.assertEqual(text.detect_lang("Hello world"), "en")


class PronounceTests(unittest.TestCase):
    def setUp(self):
        helpers.reset()

    def test_d2_rule_applies(self):
        self.assertEqual(text.pronounce_rules(), [], "預設不附規則，只有說明那一行")
        text.save_rules([("山嵐", "山藍")])
        self.assertEqual(text.apply_pronounce("清晨的山嵐"), "清晨的山藍")

    def test_longest_first_and_save(self):
        text.save_rules([("山嵐", "山藍"), ("山嵐島", "山藍倒"), ("", "x"), ("a=b", "c")])
        self.assertEqual(text.pronounce_rules(), [("山嵐", "山藍"), ("山嵐島", "山藍倒")])
        self.assertEqual(text.apply_pronounce("山嵐島上的山嵐"), "山藍倒上的山藍")
        self.assertTrue(config.PRONOUNCE.read_text(encoding="utf-8").startswith("#"))


if __name__ == "__main__":
    unittest.main()
