import Foundation

/// 管理內附的語音服務（Python 子程序）。
///
/// app 開著服務就開著；關掉 app 服務一起停。port 上已經有人在跑語音服務時直接沿用，
/// 不另開第二份（例如 app 當掉留下的子程序）。
@Observable @MainActor
final class BackendSupervisor {
    enum State: Equatable {
        case stopped
        case starting
        case running
        case failed(String)
    }

    private(set) var state: State = .stopped
    /// 服務是 app 自己開的（false 代表沿用 port 上既有的那一份）
    private(set) var ownsProcess = false

    let port: Int
    let home: URL
    let logURL: URL

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var stopping = false
    @ObservationIgnored private var crashes = 0

    init() {
        let saved = UserDefaults.standard.integer(forKey: "servicePort")
        port = saved > 0 ? saved : 8790
        let fm = FileManager.default
        // 測試與驗收可以用 VOICE_STUDIO_HOME 指到別的資料夾，不碰正式資料
        home = ProcessInfo.processInfo.environment["VOICE_STUDIO_HOME"].map { URL(fileURLWithPath: $0) }
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("VoiceStudio", isDirectory: true)
        let logs = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/VoiceStudio", isDirectory: true)
        try? fm.createDirectory(at: logs, withIntermediateDirectories: true)
        logURL = logs.appendingPathComponent("backend.log")
    }

    var isRunning: Bool { state == .running }
    var baseURL: URL { URL(string: "http://127.0.0.1:\(port)/")! }

    /// 要用哪個 Python、在哪個資料夾啟動 `studio` 套件。
    /// 打包後用 app 內附的。直接跑 `swift run` 時沒有內附後端：從執行檔往上找專案根目錄
    /// （有 `studio/app.py` 和 `.venv` 的那一層），也可以用環境變數指定（Spec 002 C-4）。
    private var backend: (python: URL, dir: URL)? {
        let fm = FileManager.default
        if let dir = Bundle.main.resourceURL?.appendingPathComponent("backend") {
            let python = dir.appendingPathComponent("bin/python3")
            if fm.isExecutableFile(atPath: python.path) { return (python, dir) }
        }
        let env = ProcessInfo.processInfo.environment
        var candidates: [URL] = []
        if let repo = env["VOICESTUDIO_REPO"] { candidates.append(URL(fileURLWithPath: repo)) }
        var dir = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<8 {
            guard let current = dir, current.path != "/" else { break }
            candidates.append(current)
            dir = current.deletingLastPathComponent()
        }
        for repo in candidates where fm.fileExists(atPath: repo.appendingPathComponent("studio/app.py").path) {
            let python = env["VOICESTUDIO_PYTHON"].map { URL(fileURLWithPath: $0) }
                ?? repo.appendingPathComponent(".venv/bin/python")
            if fm.isExecutableFile(atPath: python.path) { return (python, repo) }
        }
        return nil
    }

    func start() async {
        state = .starting
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        if await healthy() {
            ownsProcess = false
            state = .running
            return
        }
        guard let backend else {
            state = .failed("找不到語音服務：打包的 app 用 make app 重新建置；從原始碼執行要先建好 .venv（見 README）。")
            return
        }
        do {
            try launch(python: backend.python, dir: backend.dir)
        } catch {
            state = .failed("啟動語音服務失敗：\(error.localizedDescription)")
            return
        }
        // 第一次啟動要載入模型，最多等一分鐘
        for _ in 0..<120 {
            if await healthy() {
                ownsProcess = true
                state = .running
                return
            }
            if process == nil { return }   // 已經結束，didExit 會處理
            try? await Task.sleep(for: .milliseconds(500))
        }
        state = .failed("語音服務一直沒有回應，紀錄在 \(logURL.path)")
    }

    private func launch(python: URL, dir: URL) throws {
        let p = Process()
        p.executableURL = python
        // studio 是套件，要從它的上層資料夾用 -m 啟動
        p.arguments = ["-u", "-m", "studio.app"]
        p.currentDirectoryURL = dir
        var env = ProcessInfo.processInfo.environment
        env["VOICE_STUDIO_HOME"] = home.path
        env["VOICE_STUDIO_PORT"] = String(port)
        env["PYTHONDONTWRITEBYTECODE"] = "1"   // 不往已簽章的 bundle 寫東西
        env["PYTHONNOUSERSITE"] = "1"
        // 後端會監看這個 PID：app 不在了（當掉、被強制結束）就自己收工
        env["VOICE_STUDIO_PARENT_PID"] = String(ProcessInfo.processInfo.processIdentifier)
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        p.environment = env

        let fm = FileManager.default
        if !fm.fileExists(atPath: logURL.path) {
            fm.createFile(atPath: logURL.path, contents: nil)
        }
        let log = try FileHandle(forWritingTo: logURL)
        log.seekToEndOfFile()
        p.standardOutput = log
        p.standardError = log
        p.terminationHandler = { [weak self] proc in
            let code = proc.terminationStatus
            Task { @MainActor in self?.didExit(code) }
        }
        stopping = false
        try p.run()
        process = p
    }

    private func didExit(_ code: Int32) {
        process = nil
        ownsProcess = false
        guard !stopping else {
            state = .stopped
            return
        }
        crashes += 1
        guard crashes <= 3 else {
            state = .failed("語音服務一直停止（代碼 \(code)），紀錄在 \(logURL.path)")
            return
        }
        state = .failed("語音服務停止了（代碼 \(code)），正在重新啟動…")
        Task {
            try? await Task.sleep(for: .seconds(2))
            await start()
        }
    }

    /// app 結束時呼叫：先請它自己收（SIGTERM），三秒沒收完就強制結束。
    func stop() {
        guard let p = process else { return }
        stopping = true
        p.terminate()
        let deadline = Date().addingTimeInterval(3)
        while p.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if p.isRunning {
            kill(p.processIdentifier, SIGKILL)
        }
        process = nil
        state = .stopped
    }

    func restart() async {
        stop()
        crashes = 0
        await start()
    }

    func healthy() async -> Bool {
        var req = URLRequest(url: baseURL.appending(path: "api/health"))
        req.timeoutInterval = 1.5
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }
}
