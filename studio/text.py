"""稿子的前處理：發音字典、分段、語言判斷。

所有模型都吃同樣的分段結果，每段短，模型的長度上限不會碰到，進度也才有意義。
"""
import re
from dataclasses import dataclass

from . import config

# 段與段之間補的靜音（秒）；模型本身在句尾也會留一點空白，所以句間抓短一點
PAUSE_SENTENCE = 0.12
PAUSE_LINE = 0.3
PAUSE_PARAGRAPH = 0.6

LONG_LINE = 80      # 超過這個字數的行，依句號切
LONG_SENTENCE = 120  # 句子還是太長，依逗號切

_SENTENCE_END = re.compile(r"(?<=[。！？!?；;])")
_CLAUSE_END = re.compile(r"(?<=[，,、：:])")
_CJK = re.compile(r"[぀-ヿ㐀-鿿가-힯]")


@dataclass(frozen=True)
class Segment:
    text: str
    pause_after: float


# ---------- 發音字典 ----------

def pronounce_rules():
    config.ensure_dirs()
    rules = []
    for line in config.PRONOUNCE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            src, dst = line.split("=", 1)
            if src.strip():
                rules.append((src.strip(), dst.strip()))
    return rules


def save_rules(rules):
    """表格編輯器存檔用：保留檔頭說明，規則一行一組。"""
    lines = [config.DEFAULT_PRONOUNCE.splitlines()[0]]
    for src, dst in rules:
        src, dst = (src or "").strip(), (dst or "").strip()
        if src and "=" not in src:
            lines.append(f"{src}={dst}")
    config.PRONOUNCE.write_text("\n".join(lines) + "\n", encoding="utf-8")


def apply_pronounce(text):
    # 長的詞先換，避免「山嵐島」被「山嵐」先吃掉
    for src, dst in sorted(pronounce_rules(), key=lambda r: -len(r[0])):
        text = text.replace(src, dst)
    return text


# ---------- 分段 ----------

def _split(piece, pattern, limit):
    parts = [p.strip() for p in pattern.split(piece) if p.strip()]
    out = []
    for p in parts:
        while len(p) > limit:  # 連標點都沒有的長串，只能硬切
            out.append(p[:limit])
            p = p[limit:]
        if p:
            out.append(p)
    return out


def _line_pieces(line):
    if len(line) <= LONG_LINE:
        return [line]
    pieces = []
    for sentence in _split(line, _SENTENCE_END, 10_000):
        if len(sentence) > LONG_SENTENCE:
            pieces.extend(_split(sentence, _CLAUSE_END, LONG_SENTENCE))
        else:
            pieces.append(sentence)
    return pieces


def segments(text):
    paragraphs = re.split(r"\n\s*\n", text.replace("\r\n", "\n").strip())
    result = []
    for para in paragraphs:
        lines = [l.strip() for l in para.split("\n") if l.strip()]
        for li, line in enumerate(lines):
            pieces = _line_pieces(line)
            for pi, piece in enumerate(pieces):
                if pi < len(pieces) - 1:
                    pause = PAUSE_SENTENCE
                elif li < len(lines) - 1:
                    pause = PAUSE_LINE
                else:
                    pause = PAUSE_PARAGRAPH
                result.append(Segment(piece, pause))
    if result:
        result[-1] = Segment(result[-1].text, 0.0)
    return result


def detect_lang(text):
    return "zh" if _CJK.search(text) else "en"
