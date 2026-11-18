"""使用者設定（`settings.json`）：各方式的預設模型、記憶體上限、自訂模型清單。

模型清單＝內建目錄＋自訂模型，所有地方都透過 `all_models()`／`find()` 取得，
不直接讀 `catalog.CATALOG`，自訂模型才會一視同仁。
"""
import json
import threading

from . import catalog, config, voices

DEFAULT_BUDGET_GB = 16.0
BUDGET_RANGE = (4.0, 40.0)

_lock = threading.Lock()


def _read():
    try:
        return json.loads(config.SETTINGS.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def _write(data):
    tmp = config.SETTINGS.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(config.SETTINGS)


def custom_models():
    return tuple(catalog.spec_from_dict(d) for d in _read().get("custom_models", []))


def all_models():
    return catalog.CATALOG + custom_models()


def find(model_id):
    return next((m for m in all_models() if m.id == model_id), None)


def add_custom(spec):
    with _lock:
        data = _read()
        rows = [d for d in data.get("custom_models", []) if d.get("id") != spec.id]
        if catalog.builtin(spec.id) or any(m.repo == spec.repo for m in catalog.CATALOG):
            raise ValueError("這個模型已經在內建目錄裡了")
        rows.append(spec.to_dict())
        data["custom_models"] = rows
        _write(data)


def remove_custom(model_id):
    with _lock:
        data = _read()
        data["custom_models"] = [d for d in data.get("custom_models", []) if d.get("id") != model_id]
        defaults = data.get("defaults", {})
        data["defaults"] = {k: v for k, v in defaults.items() if v != model_id}
        _write(data)


def defaults():
    saved = _read().get("defaults", {})
    result = dict(catalog.DEFAULTS)
    for mode, model_id in saved.items():
        spec = find(model_id)
        if mode in catalog.MODES and spec and spec.supports(mode):
            result[mode] = model_id
    return result


def default_voice():
    """沒指定聲音時用哪一個（MCP 的呼叫端常常只給文字）；沒設定或那個聲音不在了就回 None。"""
    name = _read().get("default_voice")
    try:
        return voices.get(name)["name"] if name else None
    except ValueError:
        return None


def memory_budget_gb():
    value = _read().get("memory_budget_gb", DEFAULT_BUDGET_GB)
    try:
        return min(max(float(value), BUDGET_RANGE[0]), BUDGET_RANGE[1])
    except (TypeError, ValueError):
        return DEFAULT_BUDGET_GB


def view():
    return {"defaults": defaults(), "default_voice": default_voice(),
            "memory_budget_gb": memory_budget_gb(), "memory_budget_range": list(BUDGET_RANGE)}


def update(payload):
    """只接受認得的欄位；不合格的值丟 ValueError，整筆不寫入。"""
    with _lock:
        data = _read()
        if "defaults" in payload:
            new = dict(data.get("defaults", {}))
            for mode, model_id in (payload["defaults"] or {}).items():
                spec = find(model_id)
                if mode not in catalog.MODES:
                    raise ValueError(f"不認得的方式：{mode}")
                if not spec or not spec.supports(mode):
                    raise ValueError(f"{model_id} 不能當{catalog.MODE_LABELS[mode]}的預設模型")
                new[mode] = model_id
            data["defaults"] = new
        if "default_voice" in payload:
            name = payload["default_voice"]
            # 空字串或 null 代表不指定（用聲音庫的第一個）
            data["default_voice"] = voices.get(name)["name"] if name else None
        if "memory_budget_gb" in payload:
            try:
                budget = float(payload["memory_budget_gb"])
            except (TypeError, ValueError):
                raise ValueError("記憶體上限要是數字")
            data["memory_budget_gb"] = min(max(budget, BUDGET_RANGE[0]), BUDGET_RANGE[1])
        _write(data)
    return view()
