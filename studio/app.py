"""九官鳥：本機多模型語音產生服務。

同一個程序提供 REST（/api，九官鳥 app 用）與 MCP（/mcp，給 Claude 這類 AI 工具用）。沒有網頁介面。
業務邏輯都在同套件的其他模組，這裡只負責把它們接到 HTTP 與 MCP 上。

啟動（在專案根目錄）：.venv/bin/python -m studio.app
"""
import os

# 語音服務本身離線運作：載入模型只讀快取，不在背景偷偷連網；下載在子程序裡另外開
os.environ.setdefault("HF_HUB_OFFLINE", "1")

import json
import subprocess
import urllib.error
import urllib.request
import uuid
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any

import anyio
import uvicorn
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse
from mcp.server.mcpserver import MCPServer

from . import catalog, config, history, models, settings, text, voices
from .engine import Engine
from .jobs import Jobs
from .resolve import resolve_batch

config.ensure_dirs()
engine = Engine()
jobs = Jobs(engine)


# ---------- 組合查詢 ----------

def model_view(spec):
    defaults = settings.defaults()
    view = spec.to_dict()
    view.update(models.download_view(spec))
    view.update(
        loaded=spec.id in engine.loaded_ids(),
        loading=engine.loading == spec.id or spec.id in jobs.loading_ids(),
        default_for=[m for m, i in defaults.items() if i == spec.id],
        mode_labels=[catalog.MODE_LABELS[m] for m in spec.modes],
    )
    return view


def legacy_voices():
    """舊格式的聲音清單（仿聲＋已下載模型的配音員＋聲音描述），MCP 的 list_voices 用。"""
    result = [{k: v[k] for k in ("id", "label", "kind", "note")} for v in voices.list_voices()]
    seen = set()
    for spec in settings.all_models():
        if not spec.supports("preset") or not models.is_downloaded(spec):
            continue
        for p in spec.presets:
            if p.id.lower() in seen:
                continue
            seen.add(p.id.lower())
            result.append({"id": f"preset:{p.id}", "label": p.label, "kind": "preset",
                           "note": f"{spec.name}・{p.note}，可加語氣指令", "model": spec.id})
    if any(s.supports("design") and models.is_downloaded(s) for s in settings.all_models()):
        result.append({"id": "design", "label": "自訂聲音描述", "kind": "design",
                       "note": "用一句話描述想要的聲音，每次產生的音色可能略有不同"})
    return result


def submit(payload):
    return jobs.submit(resolve_batch(payload))


def _shared_extra_repos(spec):
    """其他已下載模型也在用的附屬模型，刪除時要留著。"""
    keep = set()
    for other in settings.all_models():
        if other.id != spec.id and models.is_downloaded(other):
            keep.update(models.repos_of(other))
    return keep


def delete_model(spec):
    engine.unload(spec.id)
    models.delete(spec, keep_repos=_shared_extra_repos(spec))
    if spec.custom:
        settings.remove_custom(spec.id)


def _fetch_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "voice-studio"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read())


def add_custom_model(repo):
    repo = (repo or "").strip().removeprefix("https://huggingface.co/").strip("/")
    if repo.count("/") != 1:
        raise ValueError("請輸入 Hugging Face 上的模型名稱，例如 mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit")
    try:
        cfg = _fetch_json(f"https://huggingface.co/{repo}/resolve/main/config.json")
        info = _fetch_json(f"https://huggingface.co/api/models/{repo}?blobs=true")
    except urllib.error.HTTPError as e:
        raise ValueError("Hugging Face 上找不到這個模型" if e.code == 404 else
                         f"Hugging Face 回應錯誤（{e.code}），可能需要登入或同意授權")
    except (urllib.error.URLError, TimeoutError):
        raise ValueError("連不上 Hugging Face，請確認網路後再試一次")
    size = sum((s.get("size") or 0) for s in info.get("siblings", [])) / 1e9
    spec = catalog.infer_custom(repo, cfg, size)
    settings.add_custom(spec)
    return model_view(spec)


def save_as_voice(item_id, name=None, label=None):
    """把成品存成聲音：逐字稿用實際唸的文字（套過發音字典），仿聲時才對得上。"""
    item = history.get(item_id)
    label = (label or "").strip() or f"{item['voice_label']}（{item['model_name']}）"
    name = voices.unique_name(name or f"saved-{item['id'][-4:]}")
    return voices.add(name, item["path"], item["spoken"], label,
                      extra={"source": {"history": item_id, "model": item["model"], "instruct": item["instruct"]}})


# ---------- MCP ----------

mcp = MCPServer(
    "myna",
    instructions=(
        "本機語音產生（多模型：Qwen3-TTS、Breeze-TTS 2、VoxCPM2、OmniVoice…）。"
        "先 list_voices 挑聲音，需要時用 list_models 看有哪些模型，"
        "再 synthesize；超過約 15 秒會先回 job_id，用 get_job 取結果。"
        "要商用的成品不要用 commercial=false 的模型。"
    ),
)


@mcp.tool(name="list_voices")
def list_voices_tool() -> list[dict]:
    """列出可用的聲音。clone:* 是仿聲（使用者自己加進聲音庫的），preset:* 是內建配音員，design 是用描述生成聲音。"""
    return legacy_voices()


@mcp.tool(name="list_models")
def list_models_tool() -> list[dict]:
    """列出已下載、可以用的模型：代號、支援的方式（clone 仿聲／preset 配音員／design 描述）、能否商用。"""
    rows = []
    for spec in settings.all_models():
        if models.is_downloaded(spec):
            rows.append({"id": spec.id, "name": spec.name, "modes": list(spec.modes),
                         "presets": [p.id for p in spec.presets], "commercial": spec.commercial,
                         "instruct_modes": list(spec.instruct_modes), "native_speed": spec.native_speed,
                         "summary": spec.summary, "default_for": [m for m, i in settings.defaults().items()
                                                                  if i == spec.id]})
    return rows


async def _wait(job, seconds=config.MCP_WAIT_SECONDS):
    deadline = anyio.current_time() + max(0, min(seconds, config.MCP_WAIT_SECONDS))
    while job.active and anyio.current_time() < deadline:
        await anyio.sleep(0.3)
    return job.view()


@mcp.tool()
async def synthesize(text: str, voice: str | None = None, model: str | None = None,
                     instruct: str | None = None, speed: float = 1.0) -> dict[str, Any]:
    """把文字唸成 wav 音檔，回傳本機路徑與網址。

    voice：list_voices 回傳的 id，不填就用聲音庫的第一個聲音。model：list_models 的模型代號，不填用該方式的預設模型。
    instruct：配音員或支援語氣的模型的語氣指令（例：熱情的廣告旁白），或 design 的聲音描述（必填）。
    speed：0.5～2.0。換行會分段唸。15 秒內沒做完會回 status=running 與 job_id，之後呼叫 get_job。
    """
    job = submit({"text": text, "voice": voice, "model": model, "instruct": instruct, "speed": speed})[0]
    return await _wait(job)


@mcp.tool(name="get_job")
async def get_job_tool(job_id: str) -> dict[str, Any]:
    """查 synthesize 的工作進度；最多等 15 秒，做完就回傳音檔路徑與網址。"""
    try:
        job = jobs.get(job_id)
    except KeyError as e:
        raise ValueError(str(e))
    return await _wait(job)


@mcp.tool(name="add_voice")
def add_voice_tool(name: str, audio_path: str, transcript: str, label: str | None = None) -> dict[str, Any]:
    """用一段本機錄音（5～20 秒、安靜、單人）新增仿聲聲音。transcript 要跟錄音一字不差。"""
    v = voices.add(name, audio_path, transcript, label)
    return {"id": v["id"], "label": v["label"], "seconds": v["seconds"]}


@mcp.tool(name="list_recent")
def list_recent_tool(limit: int = 10) -> list[dict]:
    """最近產生的音檔（新的在前）。"""
    return history.read(limit)


mcp_app = mcp.streamable_http_app(streamable_http_path="/mcp", stateless_http=True, json_response=True,
                                  host="127.0.0.1")


# ---------- REST ----------

@asynccontextmanager
async def lifespan(app):
    default = settings.find(settings.defaults()["clone"])
    if default and models.is_downloaded(default):
        jobs.submit_load(default)  # 先把最常用的模型載進來
    async with mcp.session_manager.run():
        yield


app = FastAPI(title="Voice Studio", lifespan=lifespan)


def _bad(e, code=400):
    raise HTTPException(status_code=code, detail=str(e))


def _spec_or_404(model_id):
    spec = settings.find(model_id)
    if not spec:
        raise HTTPException(status_code=404, detail=f"沒有這個模型：{model_id}")
    return spec


def _job_or_404(job_id):
    try:
        return jobs.get(job_id)
    except KeyError as e:
        raise HTTPException(status_code=404, detail=str(e))


@app.get("/api/health")
def api_health():
    return {"ok": True, "home": str(config.ROOT), "ffmpeg": bool(config.FFMPEG),
            "models_loaded": engine.loaded_ids(), "memory_budget_gb": settings.memory_budget_gb(),
            "model_cache": str(models.cache_dir())}


# 模型

@app.get("/api/models")
def api_models():
    return {"models": [model_view(s) for s in settings.all_models()], "mode_labels": catalog.MODE_LABELS}


@app.post("/api/models/custom")
async def api_add_custom(payload: dict):
    try:
        return await anyio.to_thread.run_sync(add_custom_model, payload.get("repo"))
    except ValueError as e:
        _bad(e)


@app.post("/api/models/{model_id}/download")
def api_download(model_id: str):
    spec = _spec_or_404(model_id)
    try:
        models.start(spec)
    except ValueError as e:
        _bad(e)
    return model_view(spec)


@app.delete("/api/models/{model_id}/download")
def api_cancel_download(model_id: str):
    spec = _spec_or_404(model_id)
    try:
        models.cancel(model_id)
    except ValueError as e:
        _bad(e)
    return model_view(spec)


@app.delete("/api/models/{model_id}")
async def api_delete_model(model_id: str):
    spec = _spec_or_404(model_id)
    if any(j.active and j.spec and j.spec.id == model_id for j in jobs.list(0)):
        _bad("這個模型還有工作在排隊或進行中，等它們結束再刪除")
    await anyio.to_thread.run_sync(delete_model, spec)
    return {"ok": True}


@app.post("/api/models/{model_id}/load")
def api_load(model_id: str):
    spec = _spec_or_404(model_id)
    if not models.is_downloaded(spec):
        _bad(f"{spec.name} 還沒下載")
    jobs.submit_load(spec)
    return model_view(spec)


@app.post("/api/models/{model_id}/unload")
def api_unload(model_id: str):
    spec = _spec_or_404(model_id)
    engine.unload(model_id)
    return model_view(spec)


# 設定

@app.get("/api/settings")
def api_settings():
    return settings.view()


@app.put("/api/settings")
def api_put_settings(payload: dict):
    try:
        return settings.update(payload)
    except ValueError as e:
        _bad(e)


# 聲音庫

@app.get("/api/voices")
def api_voices():
    script = config.SCRIPT.read_text(encoding="utf-8").strip() if config.SCRIPT.exists() else ""
    return {"voices": legacy_voices(), "library": voices.list_voices(),
            "script": script or config.DEFAULT_SCRIPT}


@app.post("/api/voices")
async def api_add_voice(name: str = Form(...), transcript: str = Form(...), label: str = Form(""),
                        file: UploadFile = File(...)):
    tmp = config.OUT / f".upload-{uuid.uuid4().hex}{Path(file.filename or '').suffix or '.bin'}"
    tmp.write_bytes(await file.read())
    try:
        return await anyio.to_thread.run_sync(voices.add, name, str(tmp), transcript, label or None)
    except (ValueError, subprocess.CalledProcessError) as e:
        _bad(e)
    finally:
        tmp.unlink(missing_ok=True)


@app.patch("/api/voices/{name}")
def api_update_voice(name: str, payload: dict):
    try:
        return voices.update(name, payload.get("label"), payload.get("transcript"))
    except ValueError as e:
        _bad(e)


@app.delete("/api/voices/{name}")
def api_delete_voice(name: str):
    try:
        voices.delete(name)
    except ValueError as e:
        _bad(e)
    return {"ok": True}


# 工作

@app.post("/api/jobs")
def api_submit(payload: dict):
    try:
        created = submit(payload)
    except ValueError as e:
        _bad(e)
    views = [j.view() for j in created]
    # 單筆維持舊格式（直接回傳工作）；批次多一個 jobs 陣列
    return {**views[0], "jobs": views} if len(views) > 1 else views[0]


@app.get("/api/jobs")
def api_jobs():
    return {"jobs": [j.view() for j in jobs.list()]}


@app.get("/api/jobs/{job_id}")
def api_job(job_id: str):
    return _job_or_404(job_id).view()


@app.delete("/api/jobs/{job_id}")
def api_cancel_job(job_id: str):
    job = _job_or_404(job_id)
    try:
        jobs.cancel(job.id)
    except ValueError as e:
        _bad(e)
    return job.view()


# 紀錄

@app.get("/api/history")
def api_history(limit: int = 50):
    return {"items": history.read(limit)}


@app.delete("/api/history/{item_id}")
def api_delete(item_id: str):
    history.delete(item_id)
    return {"ok": True}


@app.post("/api/history/restore")
def api_restore(payload: dict):
    try:
        return history.restore(payload)
    except ValueError as e:
        _bad(e)


@app.post("/api/history/{item_id}/voice")
async def api_save_as_voice(item_id: str, payload: dict):
    try:
        return await anyio.to_thread.run_sync(save_as_voice, item_id, payload.get("name"), payload.get("label"))
    except ValueError as e:
        _bad(e)


@app.get("/audio/{name}")
def audio(name: str):
    path = (config.OUT / name).resolve()
    if path.parent != config.OUT.resolve() or not path.exists():
        raise HTTPException(status_code=404)
    return FileResponse(path, media_type="audio/wav", filename=name)


# 發音字典

@app.get("/api/pronounce")
def api_get_pronounce():
    config.ensure_dirs()
    return {"text": config.PRONOUNCE.read_text(encoding="utf-8"),
            "rules": [list(r) for r in text.pronounce_rules()]}


@app.put("/api/pronounce")
def api_put_pronounce(payload: dict):
    if isinstance(payload.get("rules"), list):
        text.save_rules([(r[0], r[1]) for r in payload["rules"] if isinstance(r, list) and len(r) == 2])
    else:
        config.PRONOUNCE.write_text((payload.get("text") or "").rstrip() + "\n", encoding="utf-8")
    return {"rules": len(text.pronounce_rules())}


app.mount("/", mcp_app)  # /mcp 交給 MCP；要放在所有路由後面

def _watch_parent(parent_pid):
    """app 當掉或被強制結束時跟著收工，不留下佔著記憶體與連接埠的孤兒程序。"""
    import threading
    import time

    def loop():
        while os.getppid() == parent_pid:
            time.sleep(2)
        for dl in list(models._downloads.values()):
            if dl.state == "running":
                dl.proc.terminate()
        os._exit(0)

    threading.Thread(target=loop, daemon=True, name="parent-watch").start()


if __name__ == "__main__":
    if os.environ.get("VOICE_STUDIO_PARENT_PID", "").isdigit():
        _watch_parent(int(os.environ["VOICE_STUDIO_PARENT_PID"]))
    uvicorn.run(app, host="127.0.0.1", port=config.PORT, log_level="info")
