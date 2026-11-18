import AppKit
import UniformTypeIdentifiers

/// 偏好設定存放處。指定了 VOICE_STUDIO_HOME（測試、驗收）時改用獨立的一份，
/// 才不會把正式使用中的稿子與選項蓋掉。
enum AppDefaults {
    static let store: UserDefaults = {
        if ProcessInfo.processInfo.environment["VOICE_STUDIO_HOME"] != nil,
           let test = UserDefaults(suiteName: "local.weiwei.voicestudio.test") {
            return test
        }
        return .standard
    }()

    /// 預設打開的開關：沒設定過就是開。
    static func flag(_ key: String) -> Bool { store.object(forKey: key) as? Bool ?? true }
}

/// 側欄的四個區域。
enum AppSection: String, CaseIterable, Identifiable {
    case studio, library, voices, models

    var id: String { rawValue }

    var title: String {
        switch self {
        case .studio: "產生"
        case .library: "音檔"
        case .voices: "聲音庫"
        case .models: "模型"
        }
    }

    var symbol: String {
        switch self {
        case .studio: "square.and.pencil"
        case .library: "waveform"
        case .voices: "person.wave.2"
        case .models: "shippingbox"
        }
    }
}

/// 整個 app 的畫面狀態與動作。規則的判斷交給後端與 `ComposerLogic`，這裡只負責串接。
@Observable @MainActor
final class StudioModel {
    static let shared = StudioModel()

    let supervisor = BackendSupervisor()
    let player = Player()

    // MARK: 後端資料

    var models: [ModelInfo] = []
    var voices: [Voice] = []
    var history: [HistoryItem] = []
    var jobs: [JobView] = []
    var settings: SettingsInfo?
    var ffmpeg = true
    var script = ""
    /// 第一次讀到資料之前不顯示「沒有模型」之類的空狀態，避免閃一下
    var loaded = false

    // MARK: 導覽與選取

    /// 可以用啟動參數 `-section models` 指定開在哪一區（截圖驗收用）
    var section = AppSection(rawValue: UserDefaults.standard.string(forKey: "section") ?? "") ?? .studio
    var showInspector = AppDefaults.store.object(forKey: "showInspector") as? Bool ?? true
    var selection = Set<HistoryItem.ID>()
    var selectedVoice: Voice.ID?
    /// 側欄的搜尋字；有字就在「音檔」裡篩選
    var search = ""
    /// 每次加一，側欄的搜尋欄就取得輸入焦點（⌘F）
    var searchFocus = 0
    /// 「音檔」裡正在看詳情的那一筆
    var detailItem: HistoryItem.ID?

    // MARK: 編輯中的設定

    var text = AppDefaults.store.string(forKey: "text") ?? ""
    var mode = Mode(rawValue: AppDefaults.store.string(forKey: "mode") ?? "") ?? .clone
    var voiceName = AppDefaults.store.string(forKey: "voiceName") ?? ""
    var speaker = AppDefaults.store.string(forKey: "speaker") ?? "Vivian"
    var modelChoice = AppDefaults.store.dictionary(forKey: "modelChoice") as? [String: String] ?? [:]
    var instruct = ""
    var design = AppDefaults.store.string(forKey: "design") ?? ""
    var speed = 1.0
    var compareOn = false
    var compareIDs = Set<String>()

    // MARK: 介面狀態

    var status = ""
    var statusIsError = false
    var showAddVoice = false
    var addVoiceFile: URL?
    var showAddModel = false
    var saveVoiceItem: HistoryItem?
    var modelToDelete: ModelInfo?

    @ObservationIgnored var openMainWindow: (() -> Void)?
    @ObservationIgnored private var tracker = JobTracker()
    @ObservationIgnored private var myJobs = Set<String>()
    @ObservationIgnored private var autoplayJob: String?
    /// 已經開始邊產生邊播的那一筆（自己送出的）；使用者中途改播別的，就不再幫它自動播
    @ObservationIgnored private var liveStarted: String?
    @ObservationIgnored private var speakQueue = SpeakQueue()
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    var client: StudioClient { StudioClient(base: supervisor.baseURL) }

    // MARK: 推導

    var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    var hasDownloadedModels: Bool { models.contains(where: \.isDownloaded) }
    var speakers: [SpeakerOption] { ComposerLogic.speakers(models) }
    var currentVoice: Voice? { voices.first { $0.name == voiceName } }
    var activeJobs: [JobView] { jobs.filter { $0.isActive && $0.kind == "synth" } }

    var usableModels: [ModelInfo] {
        ComposerLogic.usableModels(models, mode: mode, speaker: mode == .preset ? speaker : nil)
    }

    var selectedModel: ModelInfo? {
        ComposerLogic.pickModel(usableModels, preferred: modelChoice[mode.rawValue], mode: mode)
    }

    var showsInstruct: Bool { ComposerLogic.showsInstruct(selectedModel, mode: mode) }
    var speedAvailable: Bool { ComposerLogic.speedAvailable(selectedModel, ffmpeg: ffmpeg) }

    var compareTargets: [String] {
        ComposerLogic.compareTargets(enabled: compareOn, selected: compareIDs, usable: usableModels)
    }

    var blocker: String? {
        ComposerLogic.blocker(text: text, mode: mode, model: selectedModel,
                              hasDownloadedModels: hasDownloadedModels, voice: currentVoice,
                              speaker: speaker, design: design, serviceRunning: supervisor.isRunning)
    }

    var canGenerate: Bool { blocker == nil }

    func item(_ id: HistoryItem.ID?) -> HistoryItem? {
        guard let id else { return nil }
        return history.first { $0.id == id }
    }

    /// 跟目前稿子一字不差的產出：同一份稿子換模型、換聲音試出來的各個版本
    var takes: [HistoryItem] {
        let text = trimmedText
        guard !text.isEmpty else { return [] }
        return Array(history.lazy.filter { $0.text == text }.prefix(12))
    }

    var recentScripts: [RecentScript] { ComposerLogic.recentScripts(history, limit: 10) }

    var selectedItems: [HistoryItem] { history.filter { selection.contains($0.id) } }
    var selectedItem: HistoryItem? { selection.count == 1 ? item(selection.first) : nil }

    var isBusy: Bool {
        jobs.contains(where: \.isActive) || models.contains { $0.isDownloading || $0.loading }
    }

    var serviceText: String {
        switch supervisor.state {
        case .stopped: "語音服務已停止"
        case .starting: "語音服務啟動中…"
        case .running: "語音服務執行中"
        case .failed(let why): why
        }
    }

    // MARK: 啟動與同步

    func boot() async {
        await supervisor.start()
        await refresh()
        startPolling()
    }

    func refresh() async {
        guard supervisor.isRunning else { return }
        do {
            async let m = client.models()
            async let v = client.voices()
            async let h = client.history()
            async let s = client.settings()
            async let hl = client.health()
            models = try await m
            let lib = try await v
            voices = lib.library
            script = lib.script
            history = try await h
            settings = try await s
            ffmpeg = (try? await hl)?.ffmpeg ?? true
            jobs = (try? await client.jobs()) ?? jobs
            _ = tracker.update(jobs)
            speakQueue.note(jobs)
            normalizeChoices()
            loaded = true
        } catch {
            show(error: "讀不到語音服務：\(error.localizedDescription)")
        }
    }

    /// 選到的聲音或配音員不在了（被刪掉、模型被移除）就換成還在的。
    private func normalizeChoices() {
        if currentVoice == nil, let first = voices.first {
            voiceName = first.name
        }
        if !speakers.contains(where: { $0.id == speaker }), let first = speakers.first {
            speaker = first.id
        }
        if selectedVoice == nil || !voices.contains(where: { $0.id == selectedVoice }) {
            selectedVoice = voices.first?.id
        }
    }

    func persist() {
        let d = AppDefaults.store
        d.set(text, forKey: "text")
        d.set(mode.rawValue, forKey: "mode")
        d.set(voiceName, forKey: "voiceName")
        d.set(speaker, forKey: "speaker")
        d.set(modelChoice, forKey: "modelChoice")
        d.set(design, forKey: "design")
        d.set(showInspector, forKey: "showInspector")
    }

    func restartService() async {
        player.clear()
        await supervisor.restart()
        await refresh()
        startPolling()
    }

    // MARK: 輪詢

    /// 有工作或下載在跑時密集查；閒置時偶爾查一下，才看得到 Claude 經 MCP 送來的工作。
    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                // 閒置時也不能查太慢：AI 工具要九官鳥唸一句話，是靠這裡發現的
                try? await Task.sleep(for: .milliseconds(self.isBusy ? 500 : 1000))
            }
        }
    }

    private func tick() async {
        guard supervisor.isRunning, let latest = try? await client.jobs() else { return }
        if latest != jobs { jobs = latest }
        let finished = tracker.update(latest)
        if !finished.isEmpty {
            if finished.contains(where: { $0.kind == "synth" && $0.status == "done" }),
               let h = try? await client.history() {
                history = h
            }
            handle(finished)
        }
        driveLive(latest)
        if isBusy || section == .models || !finished.isEmpty,
           let m = try? await client.models(), m != models {
            models = m
        }
        let count = activeJobs.count
        NSApp?.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }

    private func handle(_ finished: [JobView]) {
        for job in finished where job.kind == "synth" {
            let mine = myJobs.remove(job.id) != nil
            let wasLive = player.live?.id == job.id
            switch job.status {
            case "done":
                let final = item(job.historyID)?.playable ?? job.playable
                if wasLive, let final {
                    // 邊產生邊播的那一筆做完了：換成完整的音檔，接在正在聽的位置
                    player.feed(id: job.id, parts: job.partURLs, total: job.segments ?? 0)
                    player.complete(id: job.id, final: final)
                    if mine { selection = [final.id] }
                } else if mine, job.id == autoplayJob, liveStarted != job.id, let final {
                    selection = [final.id]
                    if AppDefaults.flag("autoplay") { player.play(final) } else { player.load(final) }
                }
                if mine { show("完成") }
                // 人在別的 app 時，讓 Dock 圖示跳一下；AI 工具要唸的那種會出聲音，不用再跳
                if !job.wantsSpeak, NSApp?.isActive == false, AppDefaults.flag("bounceDock") {
                    NSApp?.requestUserAttention(.informationalRequest)
                }
            case "error", "cancelled":
                // 不會有完整的音檔可以接了，先播的那幾段也停下來
                if wasLive { player.clear() }
                if mine, job.status == "error" {
                    show(error: "\(job.modelName ?? "")失敗：\(job.error ?? "原因不明")")
                }
            default:
                break
            }
        }
    }

    /// 邊產生邊播，以及 AI 工具要九官鳥唸出來的那些工作。每次輪詢跑一次。
    private func driveLive(_ latest: [JobView]) {
        // 自己剛送出的那一筆：自動播放開著，第一段做好就開始播
        if let id = autoplayJob, liveStarted != id, AppDefaults.flag("autoplay"),
           let job = latest.first(where: { $0.id == id }), job.status == "running", !job.partURLs.isEmpty {
            liveStarted = id
            startLive(job)
        }
        // 正在邊產生邊播的：把新做好的段落補進去
        if let live = player.live, let job = latest.first(where: { $0.id == live.id }), job.isActive {
            player.feed(id: job.id, parts: job.partURLs, total: job.segments ?? 0)
        }
        // AI 工具要唸的：照順序，播放器閒著才播下一筆，不打斷正在播的
        speakQueue.note(latest)
        switch speakQueue.next(latest, playerIdle: player.isIdle) {
        case .live(let job):
            startLive(job)
        case .play(let job):
            if let final = item(job.historyID)?.playable ?? job.playable { player.play(final) }
        case .none:
            break
        }
    }

    private func startLive(_ job: JobView) {
        player.startLive(id: job.id, title: job.preview, subtitle: job.playableSubtitle,
                         parts: job.partURLs, total: job.segments ?? 0)
    }

    /// 停止播放（選單列用）。AI 工具排著還沒唸的也一起取消，不然停了又馬上開口。
    func stopPlayback() {
        speakQueue.flush()
        if player.live != nil { player.clear() } else { player.stop() }
    }

    // MARK: 產生

    func generateTask() {
        Task { await generate() }
    }

    func generate() async {
        guard canGenerate, let model = selectedModel else {
            if let blocker { show(error: blocker) }
            return
        }
        var payload: [String: Any] = ["text": trimmedText, "mode": mode.rawValue,
                                      "speed": speedAvailable ? speed : 1.0]
        switch mode {
        case .clone: payload["voice"] = voiceName
        case .preset: payload["speaker"] = speaker
        case .design: payload["instruct"] = design.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if showsInstruct {
            payload["instruct"] = instruct.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let targets = compareTargets
        if targets.isEmpty { payload["model"] = model.id } else { payload["models"] = targets }
        do {
            let created = try await client.submit(payload)
            myJobs.formUnion(created.map(\.id))
            autoplayJob = created.first?.id
            jobs = created + jobs.filter { j in !created.contains { $0.id == j.id } }
            show(created.count > 1 ? "已排進 \(created.count) 個模型" : "")
            startPolling()
        } catch {
            show(error: error.localizedDescription)
        }
    }

    func cancel(_ job: JobView) {
        Task {
            _ = try? await client.cancelJob(job.id)
            startPolling()
        }
    }

    func cancelAll() {
        for job in jobs where job.isActive && job.kind == "synth" { cancel(job) }
    }

    func show(_ message: String) {
        statusIsError = false
        status = message
    }

    func show(error message: String) {
        statusIsError = true
        status = message
    }

    // MARK: 音檔

    func play(_ item: HistoryItem) {
        selection = [item.id]
        player.play(item.playable)
    }

    /// 打開音檔詳情：放進播放列但不自動播。
    func showDetail(_ item: HistoryItem) {
        selection = [item.id]
        detailItem = item.id
        section = .library
        player.load(item.playable)
    }

    /// 空白鍵：選取的那筆還沒在播就播它，否則切換播放／暫停。
    func togglePlay() {
        if let item = selectedItem {
            player.toggle(item.playable)
        } else {
            player.toggle()
        }
    }

    /// 丟到垃圾桶並登記復原（⌘Z 會把檔案搬回來、紀錄放回去）。
    func delete(_ items: [HistoryItem], undo: UndoManager?) async {
        guard !items.isEmpty else { return }
        var trashed: [(item: HistoryItem, trash: URL)] = []
        for item in items {
            if player.current?.id == item.id { player.clear() }
            let moved = try? await NSWorkspace.shared.recycle([item.fileURL])
            do {
                try await client.deleteHistory(item.id)
            } catch {
                show(error: "刪除失敗：\(error.localizedDescription)")
                continue
            }
            if let trash = moved?[item.fileURL] { trashed.append((item, trash)) }
        }
        let ids = Set(items.map(\.id))
        history.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
        if let detailItem, ids.contains(detailItem) { self.detailItem = nil }
        guard !trashed.isEmpty, let undo else { return }
        undo.registerUndo(withTarget: self) { model in
            Task { @MainActor in await model.restore(trashed, undo: undo) }
        }
        undo.setActionName(items.count > 1 ? "刪除 \(items.count) 個音檔" : "刪除音檔")
    }

    private func restore(_ trashed: [(item: HistoryItem, trash: URL)], undo: UndoManager) async {
        for entry in trashed {
            do {
                try FileManager.default.moveItem(at: entry.trash, to: entry.item.fileURL)
                _ = try await client.restoreHistory(entry.item)
            } catch {
                show(error: "還原失敗：\(error.localizedDescription)")
            }
        }
        history = (try? await client.history()) ?? history
        let items = trashed.map(\.item)
        undo.registerUndo(withTarget: self) { model in
            Task { @MainActor in await model.delete(items, undo: undo) }
        }
        undo.setActionName(items.count > 1 ? "刪除 \(items.count) 個音檔" : "刪除音檔")
    }

    func reveal(_ items: [HistoryItem]) {
        NSWorkspace.shared.activateFileViewerSelecting(items.map(\.fileURL))
    }

    func copyPath(_ items: [HistoryItem]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(items.map(\.path).joined(separator: "\n"), forType: .string)
    }

    /// 把這筆的稿子與設定帶回編輯區。
    func reuse(_ item: HistoryItem) {
        text = item.text
        mode = item.mode
        switch item.mode {
        case .clone:
            let name = String(item.voice.dropFirst("clone:".count))
            if voices.contains(where: { $0.name == name }) { voiceName = name }
            instruct = item.instruct
        case .preset:
            speaker = String(item.voice.dropFirst("preset:".count))
            instruct = item.instruct
        case .design:
            design = item.instruct
        }
        if models.contains(where: { $0.id == item.model && $0.isDownloaded }) {
            modelChoice[item.mode.rawValue] = item.model
        }
        speed = item.speed
        section = .studio
    }

    func saveAsVoice(_ item: HistoryItem, label: String) async -> Bool {
        do {
            let voice = try await client.saveAsVoice(historyID: item.id, label: label)
            await refresh()
            selectedVoice = voice.id
            show("已存成聲音「\(voice.label)」")
            return true
        } catch {
            show(error: "存成聲音失敗：\(error.localizedDescription)")
            return false
        }
    }

    // MARK: 聲音庫

    func use(_ voice: Voice) {
        mode = .clone
        voiceName = voice.name
        section = .studio
    }

    func updateVoice(_ voice: Voice, label: String? = nil, transcript: String? = nil) async {
        do {
            _ = try await client.updateVoice(voice.name, label: label, transcript: transcript)
            await refresh()
        } catch {
            show(error: "儲存失敗：\(error.localizedDescription)")
        }
    }

    func delete(_ voice: Voice, undo: UndoManager?) async {
        if player.current?.id == voice.playable.id { player.clear() }
        let dir = voice.fileURL.deletingLastPathComponent()
        let files = ["wav", "txt", "json"].map { dir.appendingPathComponent("\(voice.name).\($0)") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        let moved = (try? await NSWorkspace.shared.recycle(files)) ?? [:]
        try? await client.deleteVoice(voice.name)
        await refresh()
        guard !moved.isEmpty, let undo else { return }
        undo.registerUndo(withTarget: self) { model in
            Task { @MainActor in
                for (original, trash) in moved { try? FileManager.default.moveItem(at: trash, to: original) }
                await model.refresh()
                model.selectedVoice = voice.id
            }
        }
        undo.setActionName("刪除聲音「\(voice.label)」")
    }

    func beginAddVoice(file: URL? = nil) {
        addVoiceFile = file
        showAddVoice = true
    }

    // MARK: 模型

    private func modelAction(_ work: () async throws -> Void) async {
        do {
            try await work()
            models = (try? await client.models()) ?? models
            startPolling()
        } catch {
            show(error: error.localizedDescription)
        }
    }

    func download(_ model: ModelInfo) async {
        await modelAction { _ = try await client.download(model.id) }
    }

    func cancelDownload(_ model: ModelInfo) async {
        await modelAction { _ = try await client.cancelDownload(model.id) }
    }

    func load(_ model: ModelInfo) async {
        await modelAction { _ = try await client.load(model.id) }
    }

    func unload(_ model: ModelInfo) async {
        await modelAction { _ = try await client.unload(model.id) }
    }

    func deleteModel(_ model: ModelInfo) async {
        await modelAction { try await client.deleteModel(model.id) }
    }

    func setDefault(_ model: ModelInfo, for mode: Mode) async {
        await modelAction { settings = try await client.updateSettings(["defaults": [mode.rawValue: model.id]]) }
    }

    func setAllowSpeak(_ on: Bool) async {
        await modelAction { settings = try await client.updateSettings(["allow_speak": on]) }
    }

    func setDefaultVoice(_ name: String) async {
        await modelAction { settings = try await client.updateSettings(["default_voice": name]) }
    }

    func setMemoryBudget(_ gb: Double) async {
        await modelAction { settings = try await client.updateSettings(["memory_budget_gb": gb]) }
    }

    func revealModelCache() {
        Task {
            guard let health = try? await client.health() else { return }
            NSWorkspace.shared.open(URL(fileURLWithPath: health.modelCache))
        }
    }

    /// 已載入模型估計佔用的記憶體（跟後端一樣抓檔案大小的 1.2 倍）。
    var loadedGB: Double { models.filter(\.loaded).map { $0.sizeGb * 1.2 }.reduce(0, +) }

    // MARK: 稿子與系統整合

    func importScript() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.prompt = "匯入"
        if panel.runModal() == .OK { loadScript(from: panel.url) }
    }

    @discardableResult
    func loadScript(from url: URL?) -> Bool {
        guard let url, let content = try? String(contentsOf: url, encoding: .utf8) else { return false }
        receive(text: content)
        return true
    }

    /// 從服務選單、拖到 Dock 的檔案送進來的文字。
    func receive(text incoming: String) {
        text = incoming
        section = .studio
        openMainWindow?()
        NSApp?.activate(ignoringOtherApps: true)
    }
}
