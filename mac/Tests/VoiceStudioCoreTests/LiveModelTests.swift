import XCTest
@testable import VoiceStudioCore

/// 用 app 的狀態層（StudioModel）對著真的語音服務跑一遍主要流程：產生、比較、刪除與復原、存成聲音。
/// 介面上的按鈕都只是呼叫這些方法，所以這裡過了，按鈕背後的行為就有保障。
///
/// 要先起一個測試用的服務，並指定它的連接埠與資料夾：
///   VOICE_STUDIO_TEST_PORT=8791 VOICE_STUDIO_HOME=<暫存資料夾> swift test --filter LiveModelTests
@MainActor
final class LiveModelTests: XCTestCase {
    private var model: StudioModel!

    override func setUp() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let port = env["VOICE_STUDIO_TEST_PORT"].flatMap(Int.init), env["VOICE_STUDIO_HOME"] != nil else {
            throw XCTSkip("沒有指定 VOICE_STUDIO_TEST_PORT 與 VOICE_STUDIO_HOME")
        }
        UserDefaults.standard.set(port, forKey: "servicePort")
        model = StudioModel()
        model.player.muted = true
        await model.boot()
        XCTAssertTrue(model.supervisor.isRunning, model.serviceText)
        XCTAssertFalse(model.supervisor.ownsProcess, "應該沿用已經在跑的測試服務")
    }

    override func tearDown() async throws {
        model?.player.clear()
        model = nil
    }

    private func wait(_ what: String, timeout: TimeInterval = 90, until done: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !done() {
            if Date() > deadline { return XCTFail("等不到：\(what)（\(model.status)）") }
            try await Task.sleep(for: .milliseconds(200))
        }
    }

    func testBootLoadsEverything() {
        XCTAssertEqual(model.models.count, 8)
        XCTAssertTrue(model.hasDownloadedModels)
        XCTAssertNotNil(model.currentVoice)
        XCTAssertNotNil(model.settings)
        XCTAssertFalse(model.script.isEmpty)
    }

    func testGenerateSelectsAndPlaysResult() async throws {
        let before = Set(model.history.map(\.id))
        model.text = "這是九官鳥的整合測試。"
        model.mode = .clone
        model.modelChoice["clone"] = "omnivoice"
        model.compareOn = false
        XCTAssertNil(model.blocker)
        await model.generate()
        XCTAssertFalse(model.statusIsError, model.status)
        XCTAssertEqual(model.activeJobs.count, 1, "送出後佇列要立刻看得到")

        try await wait("新的音檔") { model.history.contains { !before.contains($0.id) } }
        let item = try XCTUnwrap(model.history.first { !before.contains($0.id) })
        XCTAssertEqual(item.model, "omnivoice")
        XCTAssertEqual(item.text, "這是九官鳥的整合測試。")
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.path))
        try await wait("自動選取並播放") { model.selection == [item.id] && model.player.current?.id == item.id }
        try await wait("波形") { !model.player.peaks.isEmpty }
    }

    func testCompareProducesOneBatch() async throws {
        let before = Set(model.history.map(\.id))
        model.text = "比較兩個模型。"
        model.mode = .clone
        model.compareOn = true
        model.compareIDs = ["omnivoice", "voxcpm2"]
        XCTAssertEqual(model.compareTargets, ["voxcpm2", "omnivoice"])
        await model.generate()
        XCTAssertFalse(model.statusIsError, model.status)

        try await wait("兩筆產出") { model.history.filter { !before.contains($0.id) }.count == 2 }
        let made = model.history.filter { !before.contains($0.id) }
        XCTAssertEqual(Set(made.map(\.model)), ["omnivoice", "voxcpm2"])
        XCTAssertEqual(Set(made.map(\.batch)).count, 1)
        XCTAssertNotNil(made[0].batch)
        // 稿子沒變，兩筆都算「這份稿子的版本」；稿子一改就不算
        XCTAssertTrue(Set(made.map(\.id)).isSubset(of: Set(model.takes.map(\.id))))
        XCTAssertTrue(model.takes.allSatisfy { $0.text == "比較兩個模型。" })
        model.text = "換一份稿子"
        XCTAssertTrue(model.takes.isEmpty)
    }

    func testDesignRequiresDescriptionThenWorks() async throws {
        model.text = "用描述產生聲音。"
        model.mode = .design
        model.modelChoice["design"] = "voxcpm2"
        model.design = ""
        XCTAssertEqual(model.blocker, "先寫聲音描述")
        await model.generate()
        XCTAssertTrue(model.statusIsError)

        let before = Set(model.history.map(\.id))
        model.design = "一位三十歲左右的台灣女性，聲音溫暖親切"
        model.compareOn = false
        await model.generate()
        try await wait("描述的產出") { model.history.contains { !before.contains($0.id) } }
        let item = try XCTUnwrap(model.history.first { !before.contains($0.id) })
        XCTAssertEqual(item.mode, .design)
        XCTAssertEqual(item.instruct, model.design)
    }

    func testDeleteCanBeUndone() async throws {
        let item = try XCTUnwrap(model.history.last, "測試服務裡要先有至少一個音檔")
        let undo = UndoManager()
        await model.delete([item], undo: undo)
        XCTAssertFalse(model.history.contains { $0.id == item.id })
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.path), "檔案應該進了垃圾桶")
        XCTAssertTrue(undo.canUndo)
        XCTAssertEqual(undo.undoActionName, "刪除音檔")

        undo.undo()
        try await wait("復原") { model.history.contains { $0.id == item.id } }
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.path))
        XCTAssertEqual(model.history.map(\.id), model.history.sorted { $0.created > $1.created }.map(\.id),
                       "還原後仍照時間排序")
    }

    func testSaveAsVoiceThenDeleteAndUndo() async throws {
        let item = try XCTUnwrap(model.history.first { $0.seconds >= 2 })
        let count = model.voices.count
        let saved = await model.saveAsVoice(item, label: "整合測試的聲音")
        XCTAssertTrue(saved, model.status)
        XCTAssertEqual(model.voices.count, count + 1)
        let voice = try XCTUnwrap(model.voices.first { $0.label == "整合測試的聲音" })
        XCTAssertEqual(voice.transcript, item.spoken)

        model.use(voice)
        XCTAssertEqual(model.section, .studio)
        XCTAssertEqual(model.currentVoice?.id, voice.id)

        let undo = UndoManager()
        await model.delete(voice, undo: undo)
        XCTAssertEqual(model.voices.count, count)
        XCTAssertNotEqual(model.voiceName, voice.name, "選到的聲音被刪掉後要換成還在的")
        undo.undo()
        try await wait("聲音復原") { model.voices.count == count + 1 }

        // 收尾：直接請服務刪掉（不經垃圾桶），不留測試資料
        try await model.client.deleteVoice(voice.name)
    }

    func testReuseBringsSettingsBack() throws {
        let item = try XCTUnwrap(model.history.first { $0.mode == .clone })
        model.text = ""
        model.section = .library
        model.reuse(item)
        XCTAssertEqual(model.text, item.text)
        XCTAssertEqual(model.mode, .clone)
        XCTAssertEqual(model.selectedModel?.id, item.model)
        XCTAssertEqual(model.section, .studio)
    }

    func testModelLoadAndUnload() async throws {
        let moss = try XCTUnwrap(model.models.first { $0.id == "moss-tts-nano" })
        await model.unload(moss)
        XCTAssertFalse(try XCTUnwrap(model.models.first { $0.id == moss.id }).loaded)
        await model.load(moss)
        try await wait("載入") { model.models.first { $0.id == moss.id }?.loaded == true }
        await model.unload(moss)
        XCTAssertFalse(try XCTUnwrap(model.models.first { $0.id == moss.id }).loaded)
    }

    // MARK: Spec 003 — 邊產生邊播、AI 工具直接唸出來（驗收 C5～C8）

    private func speak(_ text: String) async throws -> (code: Int, body: [String: Any]) {
        var req = URLRequest(url: model.supervisor.baseURL.appending(path: "api/speak"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["text": text, "model": "omnivoice"])
        let (data, resp) = try await URLSession.shared.data(for: req)
        let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return ((resp as? HTTPURLResponse)?.statusCode ?? 0, body)
    }

    private let longScript = (1...6).map { "這是第 \($0) 段，用來確認稿子還沒整份做完的時候，前面做好的段落就已經開始播了。" }
        .joined(separator: "\n")

    func testLivePlaybackStartsBeforeJobFinishes() async throws {
        let before = Set(model.history.map(\.id))
        model.text = longScript
        model.mode = .clone
        model.modelChoice["clone"] = "omnivoice"
        model.compareOn = false
        model.player.rate = 2
        await model.generate()
        XCTAssertFalse(model.statusIsError, model.status)

        try await wait("邊產生邊播") { model.player.live != nil }
        XCTAssertEqual(model.activeJobs.count, 1, "開始播的時候，工作還在產生")
        XCTAssertTrue(model.player.isPlaying)
        XCTAssertEqual(model.player.live?.total, 6)
        XCTAssertTrue(model.history.allSatisfy { before.contains($0.id) }, "完整的音檔還沒出現")

        try await wait("換成完整的音檔", timeout: 180) { model.player.live == nil && model.player.current != nil }
        let item = try XCTUnwrap(model.history.first { !before.contains($0.id) })
        XCTAssertEqual(model.player.current?.id, item.id)
        XCTAssertEqual(model.selection, [item.id])
        XCTAssertEqual(model.player.duration, item.seconds, accuracy: 0.2)
        XCTAssertGreaterThan(model.player.position, 1, "接在已經播過的位置，不是從頭")
        try await wait("波形") { !model.player.peaks.isEmpty }
    }

    func testCancelStopsLivePlayback() async throws {
        let before = model.history.count
        model.text = longScript
        model.mode = .clone
        model.modelChoice["clone"] = "omnivoice"
        model.compareOn = false
        await model.generate()
        try await wait("邊產生邊播") { model.player.live != nil }
        model.cancelAll()
        try await wait("播放停止") { model.player.current == nil && model.activeJobs.isEmpty }
        XCTAssertFalse(model.player.isPlaying)
        XCTAssertEqual(model.history.count, before, "取消的工作不留紀錄")
    }

    func testSpeakPlaysTwoInOrder() async throws {
        model.player.rate = 2
        let a = try await speak("第一句：測試都通過了。")
        let b = try await speak("第二句：可以合併了。")
        XCTAssertEqual([a.code, b.code], [200, 200])
        XCTAssertEqual(a.body["speak"] as? Bool, true)

        // 記下播放器依序播了什麼，以及每一句有沒有播到最後
        var order: [String] = []
        var finished = Set<String>()
        let deadline = Date().addingTimeInterval(120)
        while finished.count < 2, Date() < deadline {
            if let title = model.player.current?.title, title.contains("句：") {
                if order.last != title { order.append(title) }
                if !model.player.isPlaying, model.player.duration > 0,
                   model.player.position >= model.player.duration - 0.05 { finished.insert(title) }
            }
            try await Task.sleep(for: .milliseconds(40))
        }
        XCTAssertEqual(order, ["第一句：測試都通過了。", "第二句：可以合併了。"])
        XCTAssertEqual(finished.count, 2, "兩句都要播完，第二句不能打斷第一句")
        XCTAssertTrue(model.history.contains { $0.text == "第二句：可以合併了。" }, "唸過的留在音檔裡")
    }

    func testSpeakRespectsSwitch() async throws {
        await model.setAllowSpeak(false)
        XCTAssertEqual(model.settings?.allowSpeak, false)
        let refused = try await speak("這句不該出聲。")
        await model.setAllowSpeak(true)
        XCTAssertEqual(refused.code, 400)
        XCTAssertTrue((refused.body["detail"] as? String ?? "").contains("synthesize"))
        try await Task.sleep(for: .seconds(2))
        XCTAssertFalse(model.history.contains { $0.text == "這句不該出聲。" })
        XCTAssertEqual(model.settings?.allowSpeak, true)
    }
}
