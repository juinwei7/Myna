import XCTest
@testable import VoiceStudioCore

/// Spec 002 驗收 A：純邏輯。資料用後端實際回傳的 JSON 樣本（Fixtures）。
final class LogicTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func models() throws -> [ModelInfo] {
        struct Response: Codable { let models: [ModelInfo] }
        return try StudioClient.decoder.decode(Response.self, from: try fixture("models")).models
    }

    /// 把樣本裡的某些模型改成未下載，模擬不同的安裝狀態。
    private func models(downloaded ids: Set<String>) throws -> [ModelInfo] {
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: try fixture("models")) as? [String: Any])
        var rows = try XCTUnwrap(raw["models"] as? [[String: Any]])
        for i in rows.indices {
            let id = rows[i]["id"] as? String ?? ""
            rows[i]["state"] = ids.contains(id) ? "downloaded" : "available"
        }
        raw["models"] = rows
        struct Response: Codable { let models: [ModelInfo] }
        let data = try JSONSerialization.data(withJSONObject: raw)
        return try StudioClient.decoder.decode(Response.self, from: data).models
    }

    // MARK: A1 可用模型

    func testUsableModelsFilterByModeAndDownload() throws {
        let all = try models(downloaded: ["qwen3-1.7b-base", "voxcpm2", "qwen3-1.7b-custom"])
        XCTAssertEqual(ComposerLogic.usableModels(all, mode: .clone).map(\.id), ["qwen3-1.7b-base", "voxcpm2"])
        XCTAssertEqual(ComposerLogic.usableModels(all, mode: .design).map(\.id), ["voxcpm2"])
        XCTAssertEqual(ComposerLogic.usableModels(all, mode: .preset, speaker: "vivian").map(\.id),
                       ["qwen3-1.7b-custom"])
        XCTAssertTrue(ComposerLogic.usableModels(all, mode: .preset, speaker: "Nobody").isEmpty)
    }

    func testSpeakersAreUniqueAndOnlyFromDownloadedModels() throws {
        XCTAssertTrue(ComposerLogic.speakers(try models(downloaded: ["voxcpm2"])).isEmpty)
        let speakers = ComposerLogic.speakers(try models(downloaded: ["qwen3-1.7b-custom"]))
        XCTAssertEqual(speakers.count, 9)
        XCTAssertEqual(speakers.first?.id, "Vivian")
        XCTAssertEqual(Set(speakers.map(\.id)).count, speakers.count)
    }

    // MARK: A2 預設選擇

    func testPickModelPrefersChoiceThenDefaultThenFirst() throws {
        let all = try models(downloaded: ["qwen3-1.7b-base", "voxcpm2", "omnivoice"])
        let usable = ComposerLogic.usableModels(all, mode: .clone)
        XCTAssertEqual(ComposerLogic.pickModel(usable, preferred: "omnivoice", mode: .clone)?.id, "omnivoice")
        XCTAssertEqual(ComposerLogic.pickModel(usable, preferred: nil, mode: .clone)?.id, "qwen3-1.7b-base")
        XCTAssertEqual(ComposerLogic.pickModel(usable, preferred: "deleted-model", mode: .clone)?.id, "qwen3-1.7b-base")

        // 預設的模型沒下載，就退到第一個可用的
        let noDefault = ComposerLogic.usableModels(try models(downloaded: ["voxcpm2", "omnivoice"]), mode: .clone)
        XCTAssertEqual(ComposerLogic.pickModel(noDefault, preferred: nil, mode: .clone)?.id, "voxcpm2")
        XCTAssertNil(ComposerLogic.pickModel([], preferred: nil, mode: .clone))
    }

    // MARK: A3 不能產生的原因

    func testBlockerReasons() throws {
        let all = try models()
        let model = all.first { $0.id == "voxcpm2" }
        struct VoicesResponse: Codable { let library: [Voice] }
        let voice = try StudioClient.decoder.decode(VoicesResponse.self, from: try fixture("voices")).library.first

        func blocker(text: String = "稿子", mode: Mode = .clone, model: ModelInfo? = model, has: Bool = true,
                     voice: Voice? = voice, speaker: String? = "Vivian", design: String = "溫暖女聲",
                     running: Bool = true) -> String? {
            ComposerLogic.blocker(text: text, mode: mode, model: model, hasDownloadedModels: has, voice: voice,
                                  speaker: speaker, design: design, serviceRunning: running)
        }
        XCTAssertNil(blocker())
        XCTAssertEqual(blocker(running: false), "語音服務還沒準備好")
        XCTAssertEqual(blocker(model: nil, has: false), "還沒有模型，先到「模型」下載一個")
        XCTAssertEqual(blocker(mode: .design, model: nil), "聲音描述還沒有可用的模型，先到「模型」下載")
        XCTAssertEqual(blocker(voice: nil), "先選一個聲音，或到「聲音庫」新增")
        XCTAssertEqual(blocker(mode: .preset, speaker: ""), "先選一位配音員")
        XCTAssertEqual(blocker(mode: .design, design: "  "), "先寫聲音描述")
        XCTAssertEqual(blocker(text: " \n "), "先寫稿子")
        // 描述方式不需要聲音庫的聲音
        XCTAssertNil(blocker(mode: .design, voice: nil))
    }

    // MARK: A4 語氣欄

    func testInstructVisibility() throws {
        let all = try models()
        func model(_ id: String) -> ModelInfo? { all.first { $0.id == id } }
        XCTAssertFalse(ComposerLogic.showsInstruct(model("qwen3-1.7b-base"), mode: .clone))
        XCTAssertTrue(ComposerLogic.showsInstruct(model("qwen3-1.7b-custom"), mode: .preset))
        XCTAssertTrue(ComposerLogic.showsInstruct(model("breeze-tts-2"), mode: .clone))
        XCTAssertFalse(ComposerLogic.showsInstruct(model("breeze-tts-2"), mode: .design))
        XCTAssertFalse(ComposerLogic.showsInstruct(nil, mode: .clone))
    }

    func testSpeedAvailability() throws {
        let all = try models()
        XCTAssertTrue(ComposerLogic.speedAvailable(all.first { $0.id == "omnivoice" }, ffmpeg: false))
        XCTAssertFalse(ComposerLogic.speedAvailable(all.first { $0.id == "voxcpm2" }, ffmpeg: false))
        XCTAssertTrue(ComposerLogic.speedAvailable(all.first { $0.id == "voxcpm2" }, ffmpeg: true))
    }

    // MARK: A5 比較

    func testCompareTargets() throws {
        let usable = ComposerLogic.usableModels(try models(downloaded: ["qwen3-1.7b-base", "voxcpm2", "omnivoice"]),
                                                mode: .clone)
        let picked: Set = ["omnivoice", "voxcpm2", "deleted-model"]
        XCTAssertEqual(ComposerLogic.compareTargets(enabled: true, selected: picked, usable: usable),
                       ["voxcpm2", "omnivoice"])
        XCTAssertEqual(ComposerLogic.compareTargets(enabled: false, selected: picked, usable: usable), [])
        XCTAssertEqual(ComposerLogic.compareTargets(enabled: true, selected: ["voxcpm2"], usable: usable), [])
    }

    // MARK: A10 最近的稿子

    func testRecentScriptsMergeTakesOfTheSameScript() throws {
        func item(_ id: String, _ text: String) throws -> HistoryItem {
            let json: [String: Any] = ["id": id, "created": "2026-11-18T10:00:00", "text": text, "spoken": text,
                                       "mode": "clone", "model": "voxcpm2", "model_name": "VoxCPM2",
                                       "voice": "clone:tw-female", "voice_label": "台灣女聲", "instruct": "",
                                       "speed": 1.0, "file": "\(id).wav", "path": "/tmp/\(id).wav", "seconds": 2.0]
            return try StudioClient.decoder.decode(HistoryItem.self, from: JSONSerialization.data(withJSONObject: json))
        }
        // 紀錄是新的在前
        let history = [try item("5", "甲"), try item("4", "乙"), try item("3", "甲"), try item("2", "丙"), try item("1", "甲")]
        let scripts = ComposerLogic.recentScripts(history, limit: 10)
        XCTAssertEqual(scripts.map(\.latest.id), ["5", "4", "2"], "每份稿子只列一次，用最新的那個版本代表")
        XCTAssertEqual(scripts.map(\.count), [3, 1, 1])
        XCTAssertEqual(ComposerLogic.recentScripts(history, limit: 2).map(\.latest.id), ["5", "4"])
        XCTAssertTrue(ComposerLogic.recentScripts([], limit: 5).isEmpty)
    }

    // MARK: A6 顯示文字

    func testFormatting() {
        XCTAssertEqual(Formatting.bytes(4_540_000_000), "4.5 GB")
        XCTAssertEqual(Formatting.bytes(290_000_000), "290 MB")
        XCTAssertEqual(Formatting.size(gb: 0.4), "400 MB")
        XCTAssertEqual(Formatting.size(gb: 3.2), "3.2 GB")
        XCTAssertEqual(Formatting.duration(5.04), "5.0 秒")
        XCTAssertEqual(Formatting.duration(65), "1 分 05 秒")
        XCTAssertEqual(Formatting.clock(65.9), "1:05")
        XCTAssertEqual(Formatting.clock(-1), "0:00")
        XCTAssertEqual(Formatting.percent(0.426), "43%")
        XCTAssertEqual(Formatting.percent(nil), "準備中…")
        XCTAssertEqual(Formatting.percent(1.7), "100%")
        XCTAssertEqual(Formatting.langs(["zh", "en", "xx"]), "中文、英文、xx")

        let now = Formatting.parse("2026-11-18T15:00:00")!
        XCTAssertEqual(Formatting.time("2026-11-18T09:05:00", now: now), "09:05")
        XCTAssertEqual(Formatting.time("2026-11-17T19:21:58", now: now), "11/17 19:21")
        XCTAssertEqual(Formatting.time("亂寫", now: now), "亂寫")
    }

    // MARK: A7 波形

    func testWaveformPeaks() {
        let samples: [Float] = [0, 0.5, -1, 0.25, 0, 0, 0.1, -0.2]
        XCTAssertEqual(Waveform.peaks(samples, bins: 4), [0.5, 1, 0, 0.2])
        XCTAssertEqual(Waveform.peaks([], bins: 3), [0, 0, 0])
        XCTAssertEqual(Waveform.peaks(samples, bins: 0), [])
        // 格數比取樣點多也不能當掉，而且每格都在 0～1
        let stretched = Waveform.peaks([0.3, -0.6], bins: 10)
        XCTAssertEqual(stretched.count, 10)
        XCTAssertTrue(stretched.allSatisfy { (0...1).contains($0) })
        XCTAssertEqual(Waveform.peaks([0, 0, 0], bins: 2), [0, 0])
    }

    // MARK: A8 工作追蹤

    func testJobTrackerReportsEachFinishOnce() throws {
        struct Response: Codable { let jobs: [JobView] }
        let active = try StudioClient.decoder.decode(Response.self, from: try fixture("jobs-active")).jobs
        let done = try StudioClient.decoder.decode(Response.self, from: try fixture("jobs-done")).jobs

        var tracker = JobTracker()
        XCTAssertTrue(tracker.update(active).isEmpty, "第一次看到的已結束工作不算剛完成")
        let finished = tracker.update(done)
        let wasActive = Set(active.filter(\.isActive).map(\.id))
        XCTAssertEqual(Set(finished.map(\.id)), wasActive)
        XCTAssertTrue(tracker.update(done).isEmpty, "同一筆不重複回報")
    }

    // MARK: A9 型別解碼

    func testDecodesRealBackendPayloads() throws {
        let all = try models()
        XCTAssertEqual(all.count, 8)
        let breeze = try XCTUnwrap(all.first { $0.id == "breeze-tts-2" })
        XCTAssertFalse(breeze.commercial)
        XCTAssertEqual(breeze.modes, [.clone, .design])
        XCTAssertEqual(breeze.instructModes, [.clone])
        XCTAssertTrue(try XCTUnwrap(all.first { $0.id == "omnivoice" }).nativeSpeed)

        struct VoicesResponse: Codable { let library: [Voice]; let script: String }
        let voices = try StudioClient.decoder.decode(VoicesResponse.self, from: try fixture("voices"))
        XCTAssertEqual(voices.library.map(\.name), ["my-voice", "taiwan-female"])
        XCTAssertFalse(voices.script.isEmpty)

        struct HistoryResponse: Codable { let items: [HistoryItem] }
        let history = try StudioClient.decoder.decode(HistoryResponse.self, from: try fixture("history")).items
        XCTAssertFalse(history.isEmpty)
        // 還原刪除時要把紀錄原樣送回後端，欄位名稱要轉回底線格式
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try StudioClient.encoder.encode(history[0])) as? [String: Any])
        XCTAssertNotNil(encoded["model_name"])
        XCTAssertNotNil(encoded["voice_label"])

        let settings = try StudioClient.decoder.decode(SettingsInfo.self, from: try fixture("settings"))
        XCTAssertEqual(settings.defaultModel(for: .clone), "qwen3-1.7b-base")

        struct Batch: Codable { let jobs: [JobView] }
        let batch = try StudioClient.decoder.decode(Batch.self, from: try fixture("batch")).jobs
        XCTAssertEqual(batch.count, 2)
        XCTAssertEqual(Set(batch.map(\.batch)).count, 1)

        let done = try StudioClient.decoder.decode(Batch.self, from: try fixture("jobs-done")).jobs
        XCTAssertNotNil(done.first { $0.kind == "synth" && $0.status == "done" }?.historyID)
    }

    // MARK: Spec 003 — 邊產生邊播、AI 工具直接唸出來

    private func job(_ id: String, status: String, parts: Int = 0, speak: Bool = true, at: Double = 0) throws -> JobView {
        let done = status == "done" ? #","id":"h-\#(id)","path":"/tmp/out/\#(id).wav""# : ""
        let json = #"{"job_id":"\#(id)","kind":"synth","status":"\#(status)","progress":0.5,"stage":"產生中","batch":null,"# +
            #""model":"omnivoice","model_name":"OmniVoice","queued_at":\#(at),"speak":\#(speak),"segments":3,"# +
            #""parts":\#(parts),"parts_dir":\#(parts > 0 ? "\"/tmp/parts/\(id)\"" : "null"),"# +
            #""voice_label":"台灣女聲","text":"第一段\n第二段"\#(done)}"#
        return try StudioClient.decoder.decode(JobView.self, from: Data(json.utf8))
    }

    func testJobViewLiveFields() throws {
        let running = try job("a1", status: "running", parts: 2)
        XCTAssertTrue(running.wantsSpeak)
        XCTAssertEqual(running.partURLs.map(\.path), ["/tmp/parts/a1/0001.wav", "/tmp/parts/a1/0002.wav"])
        XCTAssertEqual(running.preview, "第一段 第二段")
        XCTAssertNil(running.playable, "還沒做完的沒有完整的音檔")
        XCTAssertTrue(try job("a2", status: "queued").partURLs.isEmpty)

        let done = try XCTUnwrap(try job("a3", status: "done", parts: 3).playable)
        XCTAssertEqual(done.id, "h-a3")
        XCTAssertEqual(done.url.path, "/tmp/out/a3.wav")
        XCTAssertEqual(done.subtitle, "台灣女聲 · OmniVoice")

        // 舊版的服務沒有這些欄位，也要解得出來
        struct Response: Codable { let jobs: [JobView] }
        let old = try StudioClient.decoder.decode(Response.self, from: try fixture("jobs-active")).jobs
        XCTAssertTrue(old.allSatisfy { !$0.wantsSpeak && $0.partURLs.isEmpty })
        let settings = try StudioClient.decoder.decode(SettingsInfo.self, from: try fixture("settings"))
        XCTAssertNil(settings.allowSpeak)
    }

    func testLiveLogicAfterEachPart() {
        // 下一段已經做好：接著播
        XCTAssertEqual(LiveLogic.afterPart(0, ready: 2, finished: false, played: 3.2), .playPart(1))
        // 下一段還沒好：等
        XCTAssertEqual(LiveLogic.afterPart(1, ready: 2, finished: false, played: 6.0), .wait)
        // 整份做完：換成完整的音檔，位置是已經播過的長度（就算還有做好沒播的段落）
        XCTAssertEqual(LiveLogic.afterPart(0, ready: 3, finished: true, played: 3.2), .switchToFinal(offset: 3.2))
        XCTAssertEqual(LiveLogic.afterPart(2, ready: 3, finished: true, played: 9.5), .switchToFinal(offset: 9.5))
    }

    func testSpeakQueuePlaysInOrderWithoutInterrupting() throws {
        var queue = SpeakQueue()
        // app 剛打開：以前唸過的不重播
        queue.note([try job("old", status: "done")])
        XCTAssertEqual(queue.next([try job("old", status: "done")], playerIdle: true), .none)

        // 兩句幾乎同時送來，清單的順序跟送來的順序不一定一樣
        let first = try job("first", status: "running", at: 10)
        let second = try job("second", status: "queued", at: 11)
        let mine = try job("mine", status: "queued", speak: false, at: 12)
        queue.note([second, mine, first])
        XCTAssertEqual(queue.pending, ["first", "second"])

        // 第一句還沒有東西可以播：等它，不先播別的
        XCTAssertEqual(queue.next([first, second], playerIdle: true), .none)
        let firstDone = try job("first", status: "done", at: 10)
        // 播放器在忙：不打斷
        XCTAssertEqual(queue.next([firstDone, second], playerIdle: false), .none)
        XCTAssertEqual(queue.next([firstDone, second], playerIdle: true), .play(firstDone))

        // 第二句是長稿子：有一段做好就先播
        let secondLive = try job("second", status: "running", parts: 1, at: 11)
        XCTAssertEqual(queue.next([firstDone, secondLive], playerIdle: true), .live(secondLive))
        XCTAssertEqual(queue.next([firstDone, secondLive], playerIdle: true), .none)

        // 失敗、取消的跳過；停止播放會把排著的清掉
        queue.note([try job("bad", status: "error", at: 20), try job("third", status: "done", at: 21)])
        let third = try job("third", status: "done", at: 21)
        XCTAssertEqual(queue.next([try job("bad", status: "error", at: 20), third], playerIdle: true), .play(third))
        queue.note([try job("fourth", status: "queued", at: 30)])
        queue.flush()
        XCTAssertEqual(queue.next([try job("fourth", status: "done", at: 30)], playerIdle: true), .none)
    }
}
