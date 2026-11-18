"""驗收 F：REST 與 MCP。起一個真的 uvicorn 子程序（假引擎），用 urllib 打。

不用 TestClient：它需要 httpx，鎖定的依賴裡沒有（憲法 A5）。
"""
import json
import os
import subprocess
import sys
import time
import unittest
import urllib.error
import urllib.request
from pathlib import Path

from studio import catalog, config
from studio.tests import helpers

BASE = f"http://127.0.0.1:{config.PORT}"
REPO = Path(__file__).resolve().parents[2]


def call(method, path, body=None, headers=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method,
                                 headers={"Content-Type": "application/json", **(headers or {})})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw and raw[:1] in b"{[" else raw)
    except urllib.error.HTTPError as e:
        raw = e.read()
        return e.code, (json.loads(raw) if raw[:1] == b"{" else raw)


def poll(job_id, timeout=20):
    deadline = time.time() + timeout
    while time.time() < deadline:
        _, job = call("GET", f"/api/jobs/{job_id}")
        if job["status"] not in ("queued", "running"):
            return job
        time.sleep(0.1)
    raise TimeoutError(job_id)


class ApiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        helpers.reset()
        helpers.add_voice()
        helpers.mark_downloaded(*[m.id for m in catalog.CATALOG if m.id != "voxcpm2"])
        cls.proc = subprocess.Popen([sys.executable, "-m", "studio.app"], cwd=REPO, env=dict(os.environ),
                                    stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        for _ in range(100):
            try:
                if call("GET", "/api/health")[0] == 200:
                    return
            except OSError:
                time.sleep(0.1)
        cls.proc.kill()
        raise RuntimeError(cls.proc.stderr.read().decode()[-2000:])

    @classmethod
    def tearDownClass(cls):
        cls.proc.terminate()
        cls.proc.wait(5)

    def test_f1_models(self):
        code, data = call("GET", "/api/models")
        self.assertEqual(code, 200)
        rows = {m["id"]: m for m in data["models"]}
        self.assertEqual(len(rows), 8)
        self.assertEqual(rows["voxcpm2"]["state"], "available")
        self.assertEqual(rows["omnivoice"]["state"], "downloaded")
        self.assertEqual(rows["qwen3-1.7b-base"]["default_for"], ["clone"])
        for key in ("progress", "loaded", "commercial", "modes", "presets", "size_gb"):
            self.assertIn(key, rows["omnivoice"])

    def test_f2_submit_and_fetch_audio(self):
        code, job = call("POST", "/api/jobs", {"text": "你好", "voice": "clone:tw-female", "model": "omnivoice"})
        self.assertEqual(code, 200, job)
        done = poll(job["job_id"])
        self.assertEqual(done["status"], "done", done)
        self.assertEqual(done["model"], "omnivoice")
        code, wav = call("GET", f"/audio/{done['file']}")
        self.assertEqual(code, 200)
        self.assertTrue(wav.startswith(b"RIFF"))

    def test_f2_errors_are_400(self):
        code, body = call("POST", "/api/jobs", {"text": "你好", "voice": "clone:tw-female", "model": "voxcpm2"})
        self.assertEqual(code, 400)
        self.assertIn("還沒下載", body["detail"])

    def test_f3_batch(self):
        code, data = call("POST", "/api/jobs", {"text": "比較", "voice": "clone:tw-female",
                                                "models": ["omnivoice", "breeze-tts-2"]})
        self.assertEqual(code, 200, data)
        self.assertEqual(len(data["jobs"]), 2)
        self.assertEqual(len({j["batch"] for j in data["jobs"]}), 1)
        for j in data["jobs"]:
            self.assertEqual(poll(j["job_id"])["status"], "done")
        _, listing = call("GET", "/api/jobs")
        self.assertTrue(any(j["batch"] == data["batch"] for j in listing["jobs"]))

    def test_f4_save_as_voice(self):
        call("PUT", "/api/pronounce", {"rules": [["山嵐", "山藍"]]})
        _, job = call("POST", "/api/jobs", {"text": "山嵐歡迎你", "voice": "design", "instruct": "溫暖女聲"})
        done = poll(job["job_id"])
        code, voice = call("POST", f"/api/history/{done['id']}/voice", {"label": "存下來的聲音"})
        self.assertEqual(code, 200, voice)
        self.assertEqual((voice["label"], voice["transcript"]), ("存下來的聲音", "山藍歡迎你"))
        _, voices = call("GET", "/api/voices")
        self.assertIn(voice["id"], [v["id"] for v in voices["library"]])
        code, again = call("POST", "/api/jobs", {"text": "再唸一次", "voice": voice["id"]})
        self.assertEqual(poll(again["job_id"])["status"], "done")

    def test_f5_delete_and_restore(self):
        _, job = call("POST", "/api/jobs", {"text": "要刪除的", "voice": "clone:tw-female"})
        rec = poll(job["job_id"])
        saved = {k: rec[k] for k in ("id", "created", "text", "spoken", "mode", "model", "model_name", "voice",
                                     "voice_label", "instruct", "speed", "file", "seconds")}
        wav = (config.OUT / rec["file"]).read_bytes()
        call("DELETE", f"/api/history/{rec['id']}")
        _, items = call("GET", "/api/history")
        self.assertNotIn(rec["id"], [i["id"] for i in items["items"]])
        (config.OUT / rec["file"]).write_bytes(wav)
        code, back = call("POST", "/api/history/restore", saved)
        self.assertEqual(code, 200, back)
        _, items = call("GET", "/api/history")
        self.assertIn(rec["id"], [i["id"] for i in items["items"]])

    def test_no_web_page(self):
        """沒有網頁介面：根路徑不回頁面；REST 與 MCP 不受影響（MCP 由 test_f7_f8_mcp 驗）。"""
        self.assertEqual(call("GET", "/")[0], 404)
        self.assertEqual(call("GET", "/api/health")[0], 200)

    def test_f6_paths_rejected(self):
        self.assertEqual(call("GET", "/audio/..%2Fpronounce.txt")[0], 404)
        code, _ = call("POST", "/api/history/restore", {"id": "x", "file": "../pronounce.txt"})
        self.assertEqual(code, 400)

    def test_settings_and_pronounce(self):
        code, s = call("PUT", "/api/settings", {"defaults": {"clone": "omnivoice"}, "memory_budget_gb": 8})
        self.assertEqual((code, s["defaults"]["clone"], s["memory_budget_gb"]), (200, "omnivoice", 8.0))
        self.assertEqual(call("PUT", "/api/settings", {"defaults": {"preset": "omnivoice"}})[0], 400)
        call("PUT", "/api/settings", {"defaults": {"clone": "qwen3-1.7b-base"}})
        code, p = call("PUT", "/api/pronounce", {"rules": [["山嵐", "山藍"], ["MCP", "M C P"]]})
        self.assertEqual(p["rules"], 2)
        self.assertEqual(call("GET", "/api/pronounce")[1]["rules"], [["山嵐", "山藍"], ["MCP", "M C P"]])

    def test_voice_patch(self):
        code, v = call("PATCH", "/api/voices/tw-female", {"label": "台灣女聲 A"})
        self.assertEqual((code, v["label"]), (200, "台灣女聲 A"))
        call("PATCH", "/api/voices/tw-female", {"label": "台灣女聲"})

    def test_cancel_job(self):
        _, job = call("POST", "/api/jobs", {"text": "\n".join("第%d行" % i for i in range(40)),
                                            "voice": "clone:tw-female"})
        call("DELETE", f"/api/jobs/{job['job_id']}")
        self.assertEqual(poll(job["job_id"])["status"], "cancelled")

    def test_speak(self):
        """Spec 003 驗收 B1～B3、B6。"""
        code, job = call("POST", "/api/speak", {"text": "部署完成"})
        self.assertEqual((code, job["speak"]), (200, True))
        done = poll(job["job_id"])
        self.assertEqual((done["status"], done["speak"]), ("done", True))
        self.assertIn(done["id"], [r["id"] for r in call("GET", "/api/history")[1]["items"]])
        self.assertEqual(call("POST", "/api/speak", {"text": "  "})[0], 400)
        self.assertEqual(call("POST", "/api/speak", {"text": "你好", "voice": "preset:Vivian",
                                                     "model": "omnivoice"})[0], 400)

        self.assertIs(call("GET", "/api/settings")[1]["allow_speak"], True)
        self.assertEqual(call("PUT", "/api/settings", {"allow_speak": "no"})[0], 400)
        self.assertIs(call("PUT", "/api/settings", {"allow_speak": False})[1]["allow_speak"], False)
        try:
            code, err = call("POST", "/api/speak", {"text": "部署完成"})
            self.assertEqual(code, 400)
            self.assertIn("synthesize", err["detail"])
            code, job = call("POST", "/api/jobs", {"text": "照常產生", "voice": "clone:tw-female"})
            self.assertEqual((code, job["speak"]), (200, False))
            res = self._mcp("tools/call", {"name": "speak", "arguments": {"text": "你好"}})
            self.assertTrue(res.get("isError"), res)
        finally:
            call("PUT", "/api/settings", {"allow_speak": True})

    def test_parts_over_rest(self):
        """Spec 003 驗收 A7：分段成品的欄位從 REST 看得到。"""
        _, job = call("POST", "/api/jobs", {"text": "第一段\n第二段\n第三段", "voice": "clone:tw-female"})
        done = poll(job["job_id"])
        self.assertEqual((done["status"], done["parts"], done["segments"]), ("done", 3, 3))
        self.assertTrue((Path(done["parts_dir"]) / "0003.wav").exists())

    def _mcp(self, method, params=None):
        body = {"jsonrpc": "2.0", "id": 1, "method": method, "params": params or {}}
        code, data = call("POST", "/mcp", body, {"Accept": "application/json, text/event-stream"})
        self.assertEqual(code, 200, data)
        return data["result"]

    def test_f7_f8_mcp(self):
        tools = {t["name"] for t in self._mcp("tools/list")["tools"]}
        self.assertTrue({"list_voices", "list_models", "synthesize", "get_job", "add_voice"} <= tools)
        start = time.time()
        res = self._mcp("tools/call", {"name": "synthesize", "arguments": {"text": "你好"}})
        self.assertLess(time.time() - start, 16)
        self.assertFalse(res.get("isError"), res)
        out = res["structuredContent"]
        self.assertIn(out["status"], ("done", "running"))
        self.assertEqual(out["model"], "qwen3-1.7b-base")
        listed = self._mcp("tools/call", {"name": "list_models", "arguments": {}})["structuredContent"]
        ids = {m["id"] for m in listed["result"]}
        self.assertIn("omnivoice", ids)
        self.assertNotIn("voxcpm2", ids)

    def test_mcp_speak(self):
        """Spec 003 驗收 B4、B5。"""
        tools = {t["name"]: t for t in self._mcp("tools/list")["tools"]}
        self.assertIn("speak", tools)
        self.assertEqual(set(tools["speak"]["inputSchema"]["properties"]),
                         set(tools["synthesize"]["inputSchema"]["properties"]))
        start = time.time()
        res = self._mcp("tools/call", {"name": "speak", "arguments": {"text": "測試都過了，可以合併。"}})
        self.assertLess(time.time() - start, 2)
        self.assertFalse(res.get("isError"), res)
        out = res["structuredContent"]
        self.assertTrue(out["speak"])
        self.assertEqual(poll(out["job_id"])["status"], "done")
        res = self._mcp("tools/call", {"name": "synthesize", "arguments": {"text": "你好"}})
        self.assertFalse(res["structuredContent"]["speak"])


if __name__ == "__main__":
    unittest.main()
