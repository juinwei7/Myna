"""工作佇列：產生音檔與載入模型都排進同一條執行緒（憲法 A4）。

取消：排隊中的直接標記取消；產生中的在段與段之間停下，不留下檔案與紀錄。
"""
import threading
import time
import uuid
from collections import OrderedDict
from concurrent.futures import ThreadPoolExecutor

from .engine import Cancelled

KEEP_FINISHED = 200


class Job:
    def __init__(self, kind, r=None, spec=None, batch=None):
        self.id = uuid.uuid4().hex[:12]
        self.kind = kind            # synth | load
        self.r = r
        self.spec = spec or (r.spec if r else None)
        self.batch = batch
        self.status = "queued"      # queued | running | done | error | cancelled
        self.progress = 0.0
        self.stage = "排隊中"
        self.created = time.time()
        self.started = None
        self.finished = None
        self.result = None
        self.error = None
        self.cancel_event = threading.Event()

    @property
    def active(self):
        return self.status in ("queued", "running")

    def view(self):
        v = {"job_id": self.id, "kind": self.kind, "status": self.status,
             "progress": round(self.progress, 3), "stage": self.stage, "batch": self.batch,
             "model": self.spec.id if self.spec else None,
             "model_name": self.spec.name if self.spec else None,
             "queued_at": self.created}
        if self.r:
            v.update(voice=self.r.voice, voice_label=self.r.voice_label, mode=self.r.mode,
                     text=self.r.text[:120])
        if self.status == "done" and self.result:
            v.update(self.result)
        elif self.status == "error":
            v["error"] = self.error
        elif self.active:
            v["elapsed_seconds"] = round(time.time() - (self.started or self.created), 1)
        return v


class Jobs:
    def __init__(self, engine):
        self.engine = engine
        self._executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="voice-worker")
        self._jobs = OrderedDict()
        self._lock = threading.Lock()

    def _add(self, job):
        with self._lock:
            self._jobs[job.id] = job
            finished = [j for j in self._jobs.values() if not j.active]
            for old in finished[:-KEEP_FINISHED]:
                self._jobs.pop(old.id, None)
        self._executor.submit(self._run, job)
        return job

    def submit(self, resolved_list):
        batch = uuid.uuid4().hex[:8] if len(resolved_list) > 1 else None
        jobs = []
        for r in resolved_list:
            r.batch = batch
            jobs.append(self._add(Job("synth", r=r, batch=batch)))
        return jobs

    def submit_load(self, spec):
        for j in self._jobs.values():
            if j.kind == "load" and j.active and j.spec.id == spec.id:
                return j
        job = Job("load", spec=spec)
        job.stage = f"等待載入 {spec.name}"
        return self._add(job)

    def get(self, job_id):
        job = self._jobs.get(job_id)
        if not job:
            raise KeyError(f"找不到工作：{job_id}")
        return job

    def list(self, recent=20):
        with self._lock:
            jobs = list(self._jobs.values())
        active = [j for j in jobs if j.active]
        done = [j for j in jobs if not j.active][-recent:] if recent else []
        return active + list(reversed(done))

    def cancel(self, job_id):
        job = self.get(job_id)
        if not job.active:
            raise ValueError("這個工作已經結束了")
        job.cancel_event.set()
        if job.status == "queued":
            job.status, job.stage, job.finished = "cancelled", "已取消", time.time()
        return job

    def loading_ids(self):
        return {j.spec.id for j in self._jobs.values() if j.kind == "load" and j.active}

    def _run(self, job):
        if job.cancel_event.is_set():
            return
        job.status, job.started = "running", time.time()

        def progress(fraction, stage):
            job.progress, job.stage = fraction, stage

        try:
            if job.kind == "load":
                job.stage = f"載入 {job.spec.name}…"
                self.engine.get(job.spec)
                job.result = None
            else:
                job.result = self.engine.synth(job.r, progress, job.cancel_event.is_set)
            job.status, job.progress, job.stage = "done", 1.0, "完成"
        except Cancelled:
            job.status, job.stage = "cancelled", "已取消"
        except Exception as e:  # 錯誤原樣回給呼叫端
            job.status, job.error, job.stage = "error", str(e), "失敗"
        finally:
            job.finished = time.time()
