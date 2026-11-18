"""產生紀錄（`out/studio/history.jsonl`，一行一筆，新的在後）。

Spec 001 之前的紀錄沒有 `model`、`mode` 欄位，讀取時依舊的綁定規則補上，介面才能一致顯示。
"""
import json
import threading

from . import catalog, config, settings

_lock = threading.Lock()


def _rows():
    if not config.HISTORY.exists():
        return []
    return [json.loads(l) for l in config.HISTORY.read_text(encoding="utf-8").splitlines() if l.strip()]


def _write(rows):
    tmp = config.HISTORY.with_suffix(".tmp")
    tmp.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")
    tmp.replace(config.HISTORY)


def _legacy_fill(r):
    voice = r.get("voice", "")
    mode = r.get("mode") or ("preset" if voice.startswith("preset:") else
                             "design" if voice == "design" else "clone")
    r["mode"] = mode
    model_id = r.get("model") or catalog.DEFAULTS[mode]
    r["model"] = model_id
    if not r.get("model_name"):
        spec = settings.find(model_id)
        r["model_name"] = spec.name if spec else model_id
    r.setdefault("spoken", r.get("text", ""))
    r.setdefault("batch", None)
    return r


def _present(r):
    # 資料夾搬過家（例如搬進 app）時，路徑以現在的位置為準
    r["path"] = str(config.OUT / r["file"])
    r["url"] = f"{config.BASE_URL}/audio/{r['file']}"
    return _legacy_fill(r)


def read(limit=50):
    rows = [r for r in _rows() if (config.OUT / r["file"]).exists()]
    return [_present(r) for r in reversed(rows)][:limit]


def get(item_id):
    for r in _rows():
        if r["id"] == item_id and (config.OUT / r["file"]).exists():
            return _present(r)
    raise ValueError(f"找不到這筆紀錄：{item_id}")


def append(record):
    with _lock:
        with config.HISTORY.open("a", encoding="utf-8") as f:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")


def delete(item_id):
    with _lock:
        rows = _rows()
        for r in rows:
            if r["id"] == item_id:
                (config.OUT / r["file"]).unlink(missing_ok=True)
        _write([r for r in rows if r["id"] != item_id])


def restore(record):
    """復原刪除：app 已把檔案從垃圾桶搬回來，這裡把紀錄放回原本的時間順序。"""
    name = str(record.get("file") or "")
    path = (config.OUT / name).resolve()
    if not name or path.parent != config.OUT.resolve():
        raise ValueError("音檔不在九官鳥的資料夾裡")
    if not path.exists():
        raise ValueError("音檔不在了，沒辦法還原")
    keep = {k: v for k, v in record.items() if k not in ("path", "url")}
    with _lock:
        rows = [r for r in _rows() if r["id"] != keep.get("id")]
        rows.append(keep)
        rows.sort(key=lambda r: r.get("created", ""))
        _write(rows)
    return _present(dict(keep))
