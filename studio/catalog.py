"""模型目錄：每個模型能做什麼，全部寫成資料（憲法 A2）。

介面、驗證、MCP 說明都從這份資料推導。新增模型＝加一筆 `ModelSpec`；
只有遇到新的模型家族才需要在 `adapters.py` 多寫一個轉接器。
目錄裡的每個模型都實測過中文，結果記在 specs/001-multi-model-engine/plan.md。
"""
from dataclasses import asdict, dataclass

MODES = ("clone", "preset", "design")
MODE_LABELS = {"clone": "仿聲", "preset": "配音員", "design": "聲音描述"}


@dataclass(frozen=True)
class Preset:
    id: str
    label: str
    note: str
    lang: str = "zh"


@dataclass(frozen=True)
class ModelSpec:
    id: str
    name: str
    repo: str
    family: str
    size_gb: float
    license: str
    commercial: bool
    langs: tuple
    modes: tuple
    summary: str
    notes: str = ""
    presets: tuple = ()
    instruct_modes: tuple = ()      # 這些方式可以再加語氣指令
    native_speed: bool = False      # 模型自己能控制語速，不必事後變速
    clone_text: str = "required"    # 仿聲時逐字稿是 required 或 optional
    sample_rate: int = 24000
    extra_repos: tuple = ()         # 載入時另外需要的模型（例如音訊編碼器）
    instruct_hint: str = ""
    design_hint: str = ""
    recommended: bool = False
    custom: bool = False

    def supports(self, mode):
        return mode in self.modes

    def preset(self, speaker):
        key = (speaker or "").lower()
        return next((p for p in self.presets if p.id.lower() == key), None)

    def to_dict(self):
        d = asdict(self)
        d["presets"] = [asdict(p) for p in self.presets]
        for k in ("langs", "modes", "instruct_modes", "extra_repos"):
            d[k] = list(d[k])
        return d


QWEN_PRESETS = (
    Preset("Vivian", "Vivian", "女聲・明亮"),
    Preset("Serena", "Serena", "女聲・溫柔"),
    Preset("Uncle_Fu", "Uncle Fu", "男聲・沉穩"),
    Preset("Dylan", "Dylan", "男聲・北京腔"),
    Preset("Eric", "Eric", "男聲・四川腔"),
    Preset("Ryan", "Ryan", "男聲・英文", "en"),
    Preset("Aiden", "Aiden", "男聲・英文", "en"),
    Preset("Ono_Anna", "Ono Anna", "女聲・日文", "ja"),
    Preset("Sohee", "Sohee", "女聲・韓文", "ko"),
)

CATALOG = (
    ModelSpec(
        id="qwen3-1.7b-base", name="Qwen3-TTS 1.7B 仿聲",
        repo="mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16", family="qwen3_tts",
        size_gb=4.5, license="Apache-2.0", commercial=True, langs=("zh", "en", "ja", "ko"),
        modes=("clone",), recommended=True,
        summary="中文最穩的仿聲模型，連說話速度都會學參考錄音。",
        notes="參考錄音講得快，成品也會快；想慢一點可以用語速調整或換 OmniVoice。",
    ),
    ModelSpec(
        id="qwen3-1.7b-custom", name="Qwen3-TTS 1.7B 配音員",
        repo="mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16", family="qwen3_tts",
        size_gb=4.5, license="Apache-2.0", commercial=True, langs=("zh", "en", "ja", "ko"),
        modes=("preset",), presets=QWEN_PRESETS, instruct_modes=("preset",),
        summary="9 位內建配音員，可以用一句話指定語氣。",
        notes="中文配音員的口音偏中國大陸；要台灣口音請用仿聲。",
        instruct_hint="例：熱情、有自信的廣告旁白",
    ),
    ModelSpec(
        id="qwen3-1.7b-design", name="Qwen3-TTS 1.7B 聲音描述",
        repo="mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16", family="qwen3_tts",
        size_gb=4.5, license="Apache-2.0", commercial=True, langs=("zh", "en", "ja", "ko"),
        modes=("design",),
        summary="用一段文字描述想要的聲音，模型照描述生成。",
        notes="每次產生的音色會略有不同；滿意的那次可以存成聲音，之後用仿聲重現。",
        design_hint="例：三十歲左右的台灣男性，聲音溫暖沉穩，像廣告旁白",
    ),
    ModelSpec(
        id="qwen3-0.6b-base", name="Qwen3-TTS 0.6B 仿聲（輕量）",
        repo="mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit", family="qwen3_tts",
        size_gb=2.0, license="Apache-2.0", commercial=True, langs=("zh", "en", "ja", "ko"),
        modes=("clone",),
        summary="1.7B 的輕量版，佔用記憶體少一半以上，載入快。",
        notes="音質略遜於 1.7B，適合大量草稿或記憶體吃緊時。",
    ),
    ModelSpec(
        id="breeze-tts-2", name="Breeze-TTS 2",
        repo="mlx-community/Breeze-TTS-2-mlx-8bit", family="breeze_tts",
        size_gb=4.6, license="BreezeBlue 研究與非商業授權", commercial=False, langs=("zh", "en"),
        modes=("clone", "design"), instruct_modes=("clone",), recommended=True,
        summary="仿聲時還能用一句話指揮語氣與速度；也能用描述生成聲音。",
        notes="授權只限研究與非商業用途，產品廣告等商業用途請改用其他模型。",
        instruct_hint="例：說話慢一點，語氣溫和",
        design_hint="例：一位三十歲左右的台灣女性，聲音溫暖親切，語速適中",
    ),
    ModelSpec(
        id="voxcpm2", name="VoxCPM2",
        repo="mlx-community/VoxCPM2-8bit", family="voxcpm2",
        size_gb=3.2, license="Apache-2.0", commercial=True, langs=("zh", "en", "ja", "ko"),
        modes=("clone", "design"), clone_text="optional", sample_rate=48000, recommended=True,
        summary="48 kHz 高音質，仿聲與聲音描述都很穩。",
        notes="仿聲時逐字稿可省略，但有逐字稿通常更像。",
        design_hint="例：一位三十歲左右的台灣女性，聲音溫暖親切",
    ),
    ModelSpec(
        id="omnivoice", name="OmniVoice",
        repo="mlx-community/OmniVoice-bf16", family="omnivoice",
        size_gb=1.6, license="Apache-2.0", commercial=True, langs=("zh", "en", "ja", "ko"),
        modes=("clone", "design"), native_speed=True, recommended=True,
        summary="最快的模型，而且語速是模型自己控制，不靠事後變速。",
        notes="聲音描述用簡短的特徵詞效果最好。",
        design_hint="例：女性，青年，中音",
    ),
    ModelSpec(
        id="moss-tts-nano", name="MOSS-TTS Nano",
        repo="mlx-community/MOSS-TTS-Nano-100M", family="moss_tts_nano",
        size_gb=0.4, license="Apache-2.0", commercial=True, langs=("zh", "en", "ja", "ko"),
        modes=("clone",), clone_text="optional", sample_rate=48000,
        extra_repos=("OpenMOSS-Team/MOSS-Audio-Tokenizer-Nano",),
        summary="只有 1 億參數，下載與載入都很快。",
        notes="偶爾會唸錯字，適合試稿，不適合正式成品。",
    ),
)

# 舊行為（Spec 001 之前）各方式綁定的模型；沒指定模型時沿用，維持相容（憲法 A6）
DEFAULTS = {"clone": "qwen3-1.7b-base", "preset": "qwen3-1.7b-custom", "design": "qwen3-1.7b-design"}

# 自訂模型能接受的家族，與該家族的能力範本
FAMILY_TEMPLATES = {
    "breeze_tts": dict(modes=("clone", "design"), instruct_modes=("clone",)),
    "voxcpm2": dict(modes=("clone", "design"), clone_text="optional", sample_rate=48000),
    "omnivoice": dict(modes=("clone", "design"), native_speed=True),
    "moss_tts_nano": dict(modes=("clone",), clone_text="optional", sample_rate=48000,
                          extra_repos=("OpenMOSS-Team/MOSS-Audio-Tokenizer-Nano",)),
}


def builtin(model_id):
    return next((m for m in CATALOG if m.id == model_id), None)


def _custom_id(repo):
    return "custom:" + repo.split("/")[-1].lower()


def infer_custom(repo, config, size_gb):
    """從 Hugging Face 上的 config.json 推導自訂模型的能力；不支援的家族丟 ValueError。"""
    from mlx_audio.tts.utils import MODEL_REMAPPING

    model_type = str(config.get("model_type") or "").lower()
    family = MODEL_REMAPPING.get(model_type, model_type)
    base = dict(id=_custom_id(repo), name=repo.split("/")[-1], repo=repo, family=family,
                size_gb=round(size_gb, 2), license="請自行確認", commercial=False,
                langs=("zh", "en"), summary=f"自訂模型（{repo}）", custom=True)
    if family == "qwen3_tts":
        kind = config.get("tts_model_type")
        if kind == "base":
            return ModelSpec(**base, modes=("clone",))
        if kind == "custom_voice":
            speakers = list(((config.get("talker_config") or {}).get("spk_id") or {}).keys())
            presets = tuple(Preset(s, s.replace("_", " ").title(), "內建配音員") for s in speakers)
            if not presets:
                raise ValueError("這個 Qwen3-TTS 模型沒有配音員名單")
            return ModelSpec(**base, modes=("preset",), presets=presets, instruct_modes=("preset",))
        if kind == "voice_design":
            return ModelSpec(**base, modes=("design",))
        raise ValueError(f"看不出這個 Qwen3-TTS 模型是哪一種（tts_model_type={kind}）")
    if family in FAMILY_TEMPLATES:
        return ModelSpec(**base, **FAMILY_TEMPLATES[family])
    raise ValueError(f"還不支援這種模型（{model_type or '未知類型'}）；"
                     "目前可加入 Qwen3-TTS、Breeze-TTS、VoxCPM2、OmniVoice、MOSS-TTS Nano 系列")


def spec_from_dict(d):
    d = dict(d)
    d["presets"] = tuple(Preset(**p) for p in d.get("presets", ()))
    for k in ("langs", "modes", "instruct_modes", "extra_repos"):
        d[k] = tuple(d.get(k, ()))
    return ModelSpec(**d)
