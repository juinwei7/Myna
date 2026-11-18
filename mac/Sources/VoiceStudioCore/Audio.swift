import AVFoundation

/// 播放音檔（產出的成品、聲音庫的參考錄音），並提供播放列要畫的波形。
@Observable @MainActor
final class Player: NSObject, AVAudioPlayerDelegate {
    private(set) var current: Playable?
    private(set) var isPlaying = false
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    private(set) var peaks: [Float] = []

    @ObservationIgnored private var audio: AVAudioPlayer?
    @ObservationIgnored private var timer: Timer?
    /// 截圖驗收時靜音播放，不吵到人
    @ObservationIgnored var muted = false

    static let rates: [Float] = [0.75, 1, 1.25, 1.5, 2]
    var rate: Float = 1 {
        didSet { audio?.rate = rate }
    }

    func isPlaying(_ id: String) -> Bool { isPlaying && current?.id == id }

    /// 放進播放列但先不播（打開音檔詳情時用）。
    func load(_ item: Playable) {
        guard current != item || audio == nil else { return }
        prepare(item)
    }

    func play(_ item: Playable) {
        if current != item || audio == nil { prepare(item) }
        guard let a = audio else { return }
        if a.currentTime >= a.duration - 0.05 { a.currentTime = 0 }
        a.play()
        isPlaying = true
        startTimer()
    }

    private func prepare(_ item: Playable) {
        stop()
        guard let a = try? AVAudioPlayer(contentsOf: item.url) else { return }
        a.delegate = self
        a.volume = muted ? 0 : 1
        a.enableRate = true
        a.rate = rate
        a.prepareToPlay()
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
    }

    func clear() {
        stop()
        current = nil
        duration = 0
        peaks = []
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let a = self.audio else { return }
                self.position = a.currentTime
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
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
