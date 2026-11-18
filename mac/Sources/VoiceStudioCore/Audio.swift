import AVFoundation

/// 播放音檔（產出的成品、聲音庫的參考錄音），並提供播放列要畫的波形。
///
/// 另外有「邊產生邊播」的狀態（`live`）：長稿子還沒整份做完時，先一段一段播已經做好的；
/// 整份做完再換成完整的音檔，接在正在聽的位置。
@Observable @MainActor
final class Player: NSObject, AVAudioPlayerDelegate {
    struct Live: Equatable {
        /// 工作代號
        let id: String
        var parts: [URL]
        var total: Int
        /// 正在播（或剛播完）第幾段
        var index = 0
        /// 下一段還沒做好
        var waiting = false
        /// 前面播完的各段加起來幾秒
        var played: Double = 0
        /// 整份做完之後的完整音檔
        var final: Playable?
    }

    private(set) var current: Playable?
    private(set) var isPlaying = false
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    private(set) var peaks: [Float] = []
    private(set) var live: Live?
    /// 邊產生邊播時，正在播的這一段播到哪了（0～1）
    private(set) var partFraction: Double = 0

    @ObservationIgnored private var audio: AVAudioPlayer?
    @ObservationIgnored private var timer: Timer?
    /// 截圖驗收、測試時靜音播放，不吵到人
    @ObservationIgnored var muted = false

    static let rates: [Float] = [0.75, 1, 1.25, 1.5, 2]
    var rate: Float = 1 {
        didSet { audio?.rate = rate }
    }

    func isPlaying(_ id: String) -> Bool { isPlaying && current?.id == id }

    /// 沒在播、也沒有在等下一段：可以接新的東西來播。
    var isIdle: Bool { !isPlaying && live == nil }

    /// 邊產生邊播時整份稿子播到哪了（0～1），照段數算。
    var liveProgress: Double {
        guard let live, live.total > 0 else { return 0 }
        let done = Double(live.index) + (live.waiting ? 1 : partFraction)
        return min(1, done / Double(live.total))
    }

    /// 放進播放列但先不播（打開音檔詳情時用）。
    func load(_ item: Playable) {
        guard current != item || audio == nil else { return }
        prepare(item)
    }

    func play(_ item: Playable) {
        if live != nil, current == item {
            if !isPlaying { toggleLive() }
            return
        }
        if current != item || audio == nil { prepare(item) }
        guard let a = audio else { return }
        if a.currentTime >= a.duration - 0.05 { a.currentTime = 0 }
        a.play()
        isPlaying = true
        startTimer()
    }

    private func makePlayer(_ url: URL) -> AVAudioPlayer? {
        guard let a = try? AVAudioPlayer(contentsOf: url) else { return nil }
        a.delegate = self
        a.volume = muted ? 0 : 1
        a.enableRate = true
        a.rate = rate
        a.prepareToPlay()
        return a
    }

    private func prepare(_ item: Playable) {
        stop()
        guard let a = makePlayer(item.url) else { return }
        audio = a
        current = item
        duration = a.duration
        peaks = []
        let url = item.url
        Task.detached(priority: .utility) {
            let loaded = Waveform.load(url)
            await MainActor.run { [weak self] in
                if self?.current?.url == url { self?.peaks = loaded }
            }
        }
    }

    func toggle() {
        if live != nil {
            toggleLive()
            return
        }
        guard let a = audio, let item = current else { return }
        if a.isPlaying {
            a.pause()
            isPlaying = false
            timer?.invalidate()
        } else {
            play(item)
        }
    }

    /// 同一筆就切換播放／暫停，不同筆就換過去播。
    func toggle(_ item: Playable) {
        if current == item { toggle() } else { play(item) }
    }

    func seek(_ seconds: Double) {
        // 邊產生邊播時後面的還不存在，不能跳
        guard live == nil else { return }
        let t = min(max(seconds, 0), duration)
        audio?.currentTime = t
        position = t
    }

    func stop() {
        audio?.stop()
        audio = nil
        timer?.invalidate()
        timer = nil
        isPlaying = false
        position = 0
        partFraction = 0
        live = nil
    }

    func clear() {
        stop()
        current = nil
        duration = 0
        peaks = []
    }

    // MARK: 邊產生邊播

    /// 開始播一筆還在產生的工作。`parts` 是目前已經做好的段落，至少要有一段。
    func startLive(id: String, title: String, subtitle: String, parts: [URL], total: Int) {
        guard let first = parts.first else { return }
        stop()
        live = Live(id: id, parts: parts, total: max(total, parts.count))
        current = Playable(id: "job:\(id)", url: first, title: title, subtitle: subtitle)
        duration = 0
        peaks = []
        isPlaying = true
        playPart(0)
    }

    /// 後端又做好幾段。正在等的話就接著播。
    func feed(id: String, parts: [URL], total: Int) {
        guard var l = live, l.id == id, parts.count > l.parts.count else { return }
        l.parts = parts
        l.total = max(total, parts.count)
        live = l
        if l.waiting { advance() }
    }

    /// 整份做完了。正在播的話等這一段播完再換（才不會聽到接縫）；暫停中或正在等就馬上換。
    func complete(id: String, final: Playable) {
        guard live?.id == id else { return }
        live?.final = final
        if live?.waiting == true {
            advance()
        } else if !isPlaying {
            switchToFinal(offset: (live?.played ?? 0) + (audio?.currentTime ?? 0), playing: false)
        }
    }

    private func toggleLive() {
        guard let l = live else { return }
        if let a = audio {
            if a.isPlaying {
                a.pause()
                isPlaying = false
                timer?.invalidate()
                // 暫停的時候沒有聲音，整份已經做完就趁現在換成完整的音檔
                if l.final != nil { switchToFinal(offset: l.played + a.currentTime, playing: false) }
            } else {
                a.play()
                isPlaying = true
                startTimer()
            }
        } else {
            // 正在等下一段：先記著要不要播，做好的時候照這個決定
            isPlaying.toggle()
        }
    }

    private func playPart(_ index: Int) {
        guard var l = live, l.parts.indices.contains(index) else { return }
        l.index = index
        l.waiting = false
        live = l
        partFraction = 0
        guard let a = makePlayer(l.parts[index]) else {
            advance()  // 這一段讀不到就跳過
            return
        }
        audio = a
        if isPlaying {
            a.play()
            startTimer()
        }
    }

    /// 一段播完，或等到新東西的時候：決定接下來播什麼。
    private func advance() {
        guard var l = live else { return }
        l.played += audio?.duration ?? 0
        audio = nil
        timer?.invalidate()
        position = l.played
        partFraction = 0
        live = l
        switch LiveLogic.afterPart(l.index, ready: l.parts.count, finished: l.final != nil, played: l.played) {
        case .playPart(let next):
            playPart(next)
        case .wait:
            live?.waiting = true
        case .switchToFinal(let offset):
            switchToFinal(offset: offset, playing: isPlaying)
        }
    }

    private func switchToFinal(offset: Double, playing: Bool) {
        guard let item = live?.final else { return }
        prepare(item)  // 會結束邊產生邊播的狀態
        guard let a = audio else {
            clear()
            return
        }
        if offset >= a.duration - 0.05 {  // 已經全部聽完了
            position = duration
            return
        }
        a.currentTime = offset
        position = offset
        if playing {
            a.play()
            isPlaying = true
            startTimer()
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let a = self.audio else { return }
                self.position = (self.live?.played ?? 0) + a.currentTime
                if self.live != nil, a.duration > 0 { self.partFraction = a.currentTime / a.duration }
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finished = ObjectIdentifier(player)
        Task { @MainActor in
            // 換過播放器之後才到的通知不算
            guard let a = self.audio, ObjectIdentifier(a) == finished else { return }
            if self.live != nil {
                self.advance()
                return
            }
            self.isPlaying = false
            self.timer?.invalidate()
            self.position = self.duration
        }
    }
}

/// 錄參考聲音（新增聲音用）。錄成 48 kHz 單聲道 wav，服務端會再轉成 24 kHz。
@Observable @MainActor
final class Recorder {
    private(set) var isRecording = false
    private(set) var elapsed: Double = 0
    private(set) var level: Float = 0
    private(set) var fileURL: URL?
    var error: String?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var timer: Timer?

    func toggle() async {
        if isRecording { stop() } else { await start() }
    }

    func start() async {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            error = "沒有麥克風權限：到「系統設定 → 隱私權與安全性 → 麥克風」打開九官鳥。"
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.isMeteringEnabled = true
            guard r.record() else {
                error = "沒辦法開始錄音"
                return
            }
            recorder = r
            fileURL = nil
            elapsed = 0
            error = nil
            isRecording = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let r = self.recorder else { return }
                    self.elapsed = r.currentTime
                    r.updateMeters()
                    // -50 dB 以下當成沒聲音，換算成 0～1 給音量條
                    self.level = max(0, min(1, (r.averagePower(forChannel: 0) + 50) / 50))
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func stop() {
        guard let r = recorder else { return }
        r.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
        level = 0
        fileURL = r.url
        recorder = nil
    }
}
