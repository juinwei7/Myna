"""請求解析與驗證：把 app、MCP 送來的請求統一成 `Resolved`。

舊的聲音代號（`clone:<名稱>`、`preset:<配音員>`、`design`）照舊可用，沒指定模型時
用設定裡該方式的預設模型（憲法 A6）。錯誤訊息直接顯示給使用者，一律中文。
"""
from dataclasses import dataclass, field

from . import catalog, config, models, settings, text, voices


@dataclass
class Resolved:
    text: str
    mode: str
    spec: object
    voice: str            # 寫進紀錄的聲音代號（舊格式），例如 clone:tw-female
    voice_label: str
    instruct: str = ""
    speed: float = 1.0
    lang: str = "zh"
    ref_path: str = ""
    ref_text: str = ""
    speaker: object = None
    batch: str = None
    extra: dict = field(default_factory=dict)


def _mode_and_name(payload):
    voice = (payload.get("voice") or "").strip()
    mode = (payload.get("mode") or "").strip()
    name = ""
    if voice.startswith("clone:"):
        mode, name = mode or "clone", voice[6:]
    elif voice.startswith("preset:"):
        mode, name = mode or "preset", voice[7:]
    elif voice == "design":
        mode = mode or "design"
    else:
        name = voice
    mode = mode or "clone"
    if mode not in catalog.MODES:
        raise ValueError(f"不認得的方式：{mode}")
    if mode == "preset":
        name = (payload.get("speaker") or name).strip()
    return mode, name


def _pick_model(mode, model_id, speaker):
    if model_id:
        spec = settings.find(model_id)
        if not spec:
            raise ValueError(f"沒有這個模型：{model_id}")
        return spec
    default = settings.find(settings.defaults()[mode])
    if mode != "preset" or not speaker or (default and default.preset(speaker)):
        return default
    # 配音員屬於特定模型：預設模型沒有這位時，找有這位、且已下載的模型
    for spec in settings.all_models():
        if spec.supports("preset") and spec.preset(speaker) and models.is_downloaded(spec):
            return spec
    return default


def resolve(payload, model_id=None, check_download=True):
    body = (payload.get("text") or "").strip()
    if not body:
        raise ValueError("文字不可以是空的")
    if len(body) > config.MAX_CHARS:
        raise ValueError(f"一次最多 {config.MAX_CHARS} 字")

    mode, name = _mode_and_name(payload)
    spec = _pick_model(mode, model_id or payload.get("model"), name if mode == "preset" else "")
    if not spec.supports(mode):
        raise ValueError(f"{spec.name} 不支援{catalog.MODE_LABELS[mode]}，"
                         f"它支援：{'、'.join(catalog.MODE_LABELS[m] for m in spec.modes)}")
    if check_download and not models.is_downloaded(spec):
        raise ValueError(f"{spec.name} 還沒下載，請先到「模型」下載（約 {spec.size_gb:g} GB）")

    instruct = (payload.get("instruct") or "").strip()
    try:
        speed = float(payload.get("speed") or 1.0)
    except (TypeError, ValueError):
        raise ValueError("語速要是數字")
    r = Resolved(text=body, mode=mode, spec=spec, voice="", voice_label="",
                 speed=min(max(speed, 0.5), 2.0), lang=text.detect_lang(body))

    if mode == "clone":
        if not name:
            # 沒指定就用聲音庫的第一個（MCP 的呼叫端常常只給文字）
            library = voices.list_voices()
            if not library:
                raise ValueError("聲音庫還是空的，先新增一個聲音，或改用配音員、聲音描述")
            name = settings.default_voice() or library[0]["name"]
        v = voices.get(name)
        r.voice, r.voice_label = v["id"], v["label"]
        r.ref_path, r.ref_text = v["path"], v["transcript"]
    elif mode == "preset":
        preset = spec.preset(name)
        if not preset:
            names = "、".join(p.label for p in spec.presets)
            raise ValueError(f"{spec.name} 沒有「{name}」這位配音員，可選：{names}")
        r.speaker, r.voice, r.voice_label = preset, f"preset:{preset.id}", preset.label
    else:
        if not instruct:
            raise ValueError("聲音描述方式要先寫好聲音描述")
        r.voice, r.voice_label = "design", "聲音描述"

    # 不支援語氣的方式就不傳；舊版仿聲時也是忽略 instruct
    if mode == "design" or mode in spec.instruct_modes:
        r.instruct = instruct
    return r


def resolve_batch(payload):
    """`models: [...]` 一次比較多個模型：全部驗證通過才回傳，避免只排進一半。"""
    ids = [m for m in (payload.get("models") or []) if m]
    if not ids:
        return [resolve(payload)]
    if len(set(ids)) != len(ids):
        raise ValueError("同一個模型選了兩次")
    return [resolve(payload, model_id=m) for m in ids]
