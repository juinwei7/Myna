"""模型家族轉接器：把統一的 `Resolved` 請求轉成各家 `generate()` 的參數。

每個家族的參數名稱與慣例都不同（語言叫 lang_code 或 language、仿聲要不要逐字稿、
語氣指令要不要配 cfg_scale…），差異全部收在這裡；其他地方只看目錄宣告的能力。
"""


def _qwen3(spec, r, segment, ref_audio):
    kw = {"lang_code": {"zh": "chinese", "en": "english"}.get(r.lang, "auto")}
    if r.mode == "clone":
        kw.update(ref_audio=ref_audio, ref_text=r.ref_text)
    elif r.mode == "preset":
        kw["voice"] = r.speaker.id
        if r.instruct:
            kw["instruct"] = r.instruct
    else:
        kw["instruct"] = r.instruct
    return kw


def _breeze(spec, r, segment, ref_audio):
    kw = {}
    if r.mode == "clone":
        kw.update(ref_audio=ref_audio, ref_text=r.ref_text)
    if r.instruct:
        # 官方範例在有語氣或描述時都配 cfg_scale=4，指令才會被確實遵守
        kw.update(instruct=r.instruct, cfg_scale=4)
    return kw


def _voxcpm2(spec, r, segment, ref_audio):
    if r.mode == "clone":
        kw = {"ref_audio": ref_audio}
        if r.ref_text:
            kw["ref_text"] = r.ref_text
        return kw
    return {"instruct": r.instruct}


def natural_seconds(segment):
    """OmniVoice 沒指定長度時自己估的長度；指定語速就是拿它來換算。"""
    from mlx_audio.tts.models.omnivoice.duration import RuleDurationEstimator

    tokens = RuleDurationEstimator().estimate_duration(segment, "Nice to meet you.", 25)
    return max(10, int(tokens * 1.15)) / 25


def _omnivoice(spec, r, segment, ref_audio):
    kw = {"language": r.lang}
    if r.mode == "clone":
        kw.update(ref_audio=ref_audio, ref_text=r.ref_text)
    else:
        kw["instruct"] = r.instruct
    if abs(r.speed - 1.0) > 0.01:
        kw["duration_s"] = round(natural_seconds(segment) / r.speed, 2)
    return kw


def _moss_nano(spec, r, segment, ref_audio):
    kw = {"ref_audio": ref_audio, "mode": "voice_clone"}
    if r.ref_text:
        kw["ref_text"] = r.ref_text
    return kw


ADAPTERS = {
    "qwen3_tts": _qwen3,
    "breeze_tts": _breeze,
    "voxcpm2": _voxcpm2,
    "omnivoice": _omnivoice,
    "moss_tts_nano": _moss_nano,
}


def build(spec, r, segment, ref_audio):
    try:
        adapter = ADAPTERS[spec.family]
    except KeyError:
        raise ValueError(f"還不支援 {spec.family} 這種模型")
    return adapter(spec, r, segment, ref_audio)
