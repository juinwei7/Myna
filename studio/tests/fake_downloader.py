"""假的下載程式：照 huggingface_hub 2.x 的快取格式寫檔，取代真的連網下載。

用法跟內建下載程式一樣：python fake_downloader.py <repo...>
環境變數：FAKE_DL_FAIL=1 模擬斷網；FAKE_DL_DELAY=秒數 控制每個區塊的間隔（測取消用）。
也可以 import 後直接呼叫 make_repo() 預先放好「已下載」的模型。
"""
import hashlib
import json
import os
import sys
import time
from pathlib import Path

FILES = {"config.json": 64, "model.safetensors": 600_000}
CHUNK = 60_000


def _cache():
    return Path(os.environ["HF_HUB_CACHE"])


def _repo_dir(repo):
    return _cache() / ("models--" + repo.replace("/", "--"))


def _rev(repo):
    # 真的版本號是 git 雜湊，各模型不會相同；假的也要不同，刪除時才不會誤刪別的模型
    return hashlib.sha1(repo.encode()).hexdigest()


def _start(repo):
    rdir = _repo_dir(repo)
    rev = _rev(repo)
    for d in ("refs", "trees", "blobs", f"snapshots/{rev}"):
        (rdir / d).mkdir(parents=True, exist_ok=True)
    (rdir / "refs" / "main").write_text(rev)
    tree = {"format_version": 1, "files": {n: {"size": s, "blob_id": hashlib.sha1(f"{repo}/{n}".encode()).hexdigest()}
                                            for n, s in FILES.items()}}
    (rdir / "trees" / f"{rev}.json").write_text(json.dumps(tree))
    return rdir, tree["files"]


def _finish(rdir, name, blob_id, data):
    blob = rdir / "blobs" / blob_id
    blob.write_bytes(data)
    link = rdir / "snapshots" / (rdir / "refs" / "main").read_text() / name
    if not link.exists():
        link.symlink_to(Path("../../blobs") / blob_id)


def make_repo(repo, partial=False):
    rdir, files = _start(repo)
    for name, meta in files.items():
        if partial and name != "config.json":
            (rdir / "blobs" / f"{meta['blob_id']}.abcd1234.incomplete").write_bytes(b"\0" * 1000)
            continue
        _finish(rdir, name, meta["blob_id"], b"\0" * meta["size"])
    return rdir


def main(repos):
    if os.environ.get("FAKE_DL_FAIL") == "1":
        print("requests.exceptions.ConnectionError: Max retries exceeded", file=sys.stderr)
        sys.exit(1)
    delay = float(os.environ.get("FAKE_DL_DELAY", "0.02"))
    print(json.dumps({"total": sum(FILES.values()) * len(repos)}), flush=True)
    for repo in repos:
        rdir, files = _start(repo)
        for name, meta in files.items():
            tmp = rdir / "blobs" / f"{meta['blob_id']}.abcd1234.incomplete"
            with tmp.open("wb") as f:
                left = meta["size"]
                while left > 0:
                    n = min(CHUNK, left)
                    f.write(b"\0" * n)
                    f.flush()
                    left -= n
                    time.sleep(delay)
            tmp.unlink()
            _finish(rdir, name, meta["blob_id"], b"\0" * meta["size"])
    print(json.dumps({"done": True}), flush=True)


if __name__ == "__main__":
    main(sys.argv[1:])
