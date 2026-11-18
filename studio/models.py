"""模型檔案：是否已下載、下載、進度、取消、刪除。

檔案放在 Hugging Face 的快取（`HF_HUB_CACHE`），跟命令列工具共用，不另外複製一份。
huggingface_hub 2.x 的快取格式：
  models--<org>--<name>/refs/main           指到目前的版本
  models--<org>--<name>/trees/<版本>.json    該版本的完整檔案清單與大小
  models--<org>--<name>/snapshots/<版本>/…   下載完成的檔案（指向 blobs 的連結）
  models--<org>--<name>/blobs/*.incomplete  下載中的檔案
大檔案實體放在整個快取共用的 `blobs/` 庫，所以刪除一定要走 huggingface_hub 的清理流程，
直接刪資料夾會把共用庫裡的大檔案留成孤兒。
"""
import fnmatch
import json
import os
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

from . import config

# 跟 mlx-audio 載入模型時抓的檔案一致（mlx_audio.utils.DEFAULT_ALLOW_PATTERNS），
# README、.gitattributes 這類用不到的檔案不下載，也不列入「是否完整」的判斷
PATTERNS = ["*.json", "*.safetensors", "*.py", "*.model", "*.tiktoken", "*.txt", "*.jinja",
            "*.jsonl", "*.yaml", "*.npz", "*.pth"]
# 程式碼檔案載入時用不到（mlx-audio 自己有實作），附屬模型常常沒抓，不當成必要檔案
REQUIRED = [p for p in PATTERNS if p != "*.py"]

# 在子程序裡跑：先印出總大小，再逐一下載。子程序才能被終止，取消才做得到。
DOWNLOAD_SCRIPT = r"""
import fnmatch, json, sys
from huggingface_hub import HfApi, snapshot_download
patterns = json.loads(sys.argv[1])
repos = sys.argv[2:]
api = HfApi()
total = 0
for r in repos:
    info = api.model_info(r, files_metadata=True)
    total += sum((s.size or 0) for s in (info.siblings or [])
                 if any(fnmatch.fnmatch(s.rfilename, p) for p in patterns))
print(json.dumps({"total": total}), flush=True)
for r in repos:
    snapshot_download(r, allow_patterns=patterns)
print(json.dumps({"done": True}), flush=True)
"""


def _wanted(name, patterns):
    return any(fnmatch.fnmatch(name, p) for p in patterns)


def cache_dir():
    from huggingface_hub import constants
    return Path(constants.HF_HUB_CACHE)


def repo_dir(repo):
    return cache_dir() / ("models--" + repo.replace("/", "--"))


def repos_of(spec):
    return (spec.repo,) + tuple(spec.extra_repos)


def _incomplete_bytes(rdir):
    # 下載中的檔案可能預先配置成完整大小（稀疏檔），要看實際佔用的區塊；
    # 小檔案的區塊又會比內容大，所以兩者取小
    total = 0
    for p in (rdir / "blobs").glob("*.incomplete"):
        try:
            st = p.stat()
            total += min(st.st_blocks * 512, st.st_size)
        except OSError:
            pass
    return total


def repo_status(repo):
    """回傳 (是否完整, 已有位元組, 總位元組或 None)。"""
    rdir = repo_dir(repo)
    if not rdir.is_dir():
        return False, 0, None
    incomplete = _incomplete_bytes(rdir)
    try:
        rev = (rdir / "refs" / "main").read_text().strip()
    except OSError:
        return False, incomplete, None
    snap = rdir / "snapshots" / rev
    try:
        files = json.loads((rdir / "trees" / f"{rev}.json").read_text())["files"]
    except (OSError, ValueError, KeyError):
        files = None
    if files is None:
        # 舊版快取沒有檔案清單：快照有東西、沒有下載中的檔案就當作完整
        have = sum(p.stat().st_size for p in snap.rglob("*") if p.is_file()) if snap.is_dir() else 0
        return snap.is_dir() and have > 0 and incomplete == 0, have + incomplete, None
    files = {n: m for n, m in files.items() if _wanted(n, PATTERNS)}
    total = sum(int(f.get("size") or 0) for f in files.values())
    have, complete = 0, incomplete == 0
    for name, meta in files.items():
        path = snap / name
        if path.exists() and path.stat().st_size == int(meta.get("size") or 0):
            have += path.stat().st_size
        elif _wanted(name, REQUIRED):
            complete = False
    return complete, have + incomplete, total


def is_downloaded(spec):
    return all(repo_status(r)[0] for r in repos_of(spec))


def size_on_disk(spec):
    return sum(repo_status(r)[1] for r in repos_of(spec))


# ---------- 下載 ----------

class Download:
    def __init__(self, spec):
        self.model_id = spec.id
        self.repos = repos_of(spec)
        self.state = "running"   # running | done | failed | cancelled
        self.total = None
        self.error = None
        self.started = time.time()
        self.proc = None
        self.shown = 0.0  # 已回報過的進度；檔案從暫存搬進共用庫的瞬間量起來會變少，進度不能倒退


_downloads = {}
_lock = threading.Lock()


def _friendly_error(stderr):
    text = stderr or ""
    rules = [
        (("No space left", "Errno 28"), "磁碟空間不足"),
        (("401", "403", "GatedRepo", "gated"), "這個模型要先在 Hugging Face 登入並同意授權才能下載"),
        (("404", "RepositoryNotFound", "RevisionNotFound"), "Hugging Face 上找不到這個模型"),
        (("ConnectionError", "Max retries", "NameResolution", "nodename nor servname", "timed out",
          "OfflineModeIsEnabled", "Network is unreachable"), "連不上 Hugging Face，請確認網路後再試一次"),
    ]
    for keys, message in rules:
        if any(k in text for k in keys):
            return message
    last = [l for l in text.strip().splitlines() if l.strip()]
    return "下載失敗：" + (last[-1][:200] if last else "原因不明")


def _command(repos):
    if config.DOWNLOADER:
        return [sys.executable, "-I", config.DOWNLOADER, *repos]
    return [sys.executable, "-I", "-c", DOWNLOAD_SCRIPT, json.dumps(PATTERNS), *repos]


def start(spec):
    with _lock:
        current = _downloads.get(spec.id)
        if current and current.state == "running":
            return current
        if is_downloaded(spec):
            raise ValueError(f"{spec.name} 已經下載好了")
        dl = Download(spec)
        env = dict(os.environ, HF_HUB_DISABLE_PROGRESS_BARS="1")
        env.pop("HF_HUB_OFFLINE", None)  # 語音服務本身離線運作，只有下載要連網
        dl.proc = subprocess.Popen(_command(dl.repos), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   text=True, env=env)
        _downloads[spec.id] = dl
    threading.Thread(target=_watch, args=(dl,), daemon=True).start()
    return dl


def _watch(dl):
    stderr_tail = []

    def drain_stderr():
        for line in dl.proc.stderr:
            stderr_tail.append(line)
            del stderr_tail[:-40]

    t = threading.Thread(target=drain_stderr, daemon=True)
    t.start()
    for line in dl.proc.stdout:
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        if "total" in msg:
            dl.total = int(msg["total"])
    code = dl.proc.wait()
    t.join(timeout=2)
    if dl.state == "cancelled":
        return
    if code == 0:
        dl.state = "done"
    else:
        dl.state = "failed"
        dl.error = _friendly_error("".join(stderr_tail))


def cancel(model_id):
    dl = _downloads.get(model_id)
    if not dl or dl.state != "running":
        raise ValueError("這個模型沒有在下載")
    dl.state = "cancelled"
    dl.proc.terminate()
    try:
        dl.proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        dl.proc.kill()
    # 未完成的檔案留著，下次下載會續傳


def download_view(spec):
    """給介面用的狀態：available | downloading | downloaded，加上進度與錯誤。"""
    dl = _downloads.get(spec.id)
    have, totals = 0, []
    complete = True
    for r in repos_of(spec):
        ok, got, total = repo_status(r)
        complete &= ok
        have += got
        totals.append(total)
    view = {"downloaded_bytes": have, "total_bytes": None, "progress": None, "error": None}
    if dl and dl.state == "running":
        total = dl.total or (sum(totals) if all(t is not None for t in totals) else None)
        if total:
            dl.shown = max(dl.shown, min(have / total, 0.99))
        view.update(state="downloading", total_bytes=total, progress=dl.shown if total else None)
        return view
    if complete:
        view.update(state="downloaded", progress=1.0, total_bytes=have)
        return view
    view["state"] = "available"
    if dl and dl.state == "failed":
        view["error"] = dl.error
    return view


def wait(model_id, timeout=None):
    """測試用：等下載結束。"""
    deadline = time.time() + (timeout or 600)
    while time.time() < deadline:
        dl = _downloads.get(model_id)
        if not dl or dl.state != "running":
            return dl
        time.sleep(0.05)
    raise TimeoutError(model_id)


# ---------- 刪除 ----------

def delete(spec, keep_repos=()):
    """刪除這個模型的檔案；`keep_repos` 是其他已下載模型也在用的附屬模型。"""
    dl = _downloads.get(spec.id)
    if dl and dl.state == "running":
        cancel(spec.id)
    targets = [r for r in repos_of(spec) if r not in set(keep_repos)]
    from huggingface_hub import scan_cache_dir
    try:
        info = scan_cache_dir(cache_dir())
        revisions = [rev.commit_hash for repo in info.repos
                     if repo.repo_type == "model" and repo.repo_id in targets for rev in repo.revisions]
        if revisions:
            info.delete_revisions(*revisions).execute()
    except Exception:  # 快取掃描失敗（例如資料夾毀損）時，退回直接刪資料夾
        pass
    # 只剩下載到一半的殘骸（沒有任何版本）時，上面不會處理到
    for r in targets:
        shutil.rmtree(repo_dir(r), ignore_errors=True)
    _downloads.pop(spec.id, None)
