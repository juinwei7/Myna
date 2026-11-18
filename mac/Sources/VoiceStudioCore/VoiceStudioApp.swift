import AppKit
import SwiftUI

public struct VoiceStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = StudioModel.shared

    public init() {}

    public var body: some Scene {
        Window("九官鳥", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 860, minHeight: 520)
        }
        .defaultSize(width: 1180, height: 720)
        .commands { StudioCommands(model: model) }

        // 設定用一般視窗：可以拉大、有側欄；SwiftUI 內建的設定視窗是固定大小的分頁
        Window("設定", id: SettingsPage.windowID) {
            SettingsView()
                .environment(model)
        }
        .defaultSize(width: 820, height: 580)
        .windowResizability(.contentMinSize)

        MenuBarExtra("九官鳥", systemImage: "bird.fill") {
            MenuBarContent()
                .environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let services = ServiceProvider()
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = services
        // 明確用這個名字登記，跟 Info.plist 的 NSPortName 對上（顯示名稱是中文、執行檔是英文，不靠系統猜）
        NSRegisterServicesProvider(services, "VoiceStudio")
        // 被 kill（SIGTERM）或在終端機按 ⌃C 時也走正常的結束流程，才會把語音服務一起停掉
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
        applyLaunchOptions()
        Task { @MainActor in
            let model = StudioModel.shared
            await model.boot()
            if UserDefaults.standard.bool(forKey: "playLatest"), let first = model.history.first {
                model.player.muted = true
                model.play(first)
            }
            if let item = model.item(UserDefaults.standard.string(forKey: "detail")) {
                model.showDetail(item)
            }
        }
    }

    /// 截圖驗收用的啟動參數：`-appearance light|dark` 固定外觀、`-openSettings YES` 直接開偏好設定、
    /// `-playLatest YES` 靜音播放最新一筆（讓播放列出現）、`-detail <代號>` 直接打開那筆音檔的詳情。
    private func applyLaunchOptions() {
        let args = UserDefaults.standard
        switch args.string(forKey: "appearance") {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    /// 關掉視窗不結束：語音服務（含 MCP）繼續開著，選單列還找得到。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// 回到九官鳥時重讀一次：聲音、模型、音檔可能被 Claude（經 MCP）改過。
    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in await StudioModel.shared.refresh() }
    }

    /// 把文字檔拖到 Dock 圖示，或在 Finder 用「打開檔案的應用程式」選九官鳥。
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            _ = StudioModel.shared.loadScript(from: urls.first)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { StudioModel.shared.supervisor.stop() }
    }
}

/// 服務選單：在任何 app 選取文字 → 服務 →「用九官鳥唸出來」。
/// 方法名稱要跟 Info.plist 的 NSMessage 對上。
final class ServiceProvider: NSObject {
    @objc func speakText(_ pboard: NSPasteboard, userData: String,
                         error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pboard.string(forType: .string), !text.isEmpty else { return }
        Task { @MainActor in StudioModel.shared.receive(text: text) }
    }
}

struct StudioCommands: Commands {
    let model: StudioModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("設定⋯") { openWindow(id: SettingsPage.windowID) }
                .keyboardShortcut(",")
        }
        CommandGroup(after: .newItem) {
            Button("新增聲音…") { model.beginAddVoice() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("加入模型…") { model.showAddModel = true }
            Divider()
            Button("匯入稿子…") { model.importScript() }
                .keyboardShortcut("o")
        }
        CommandGroup(after: .textEditing) {
            Button("搜尋所有音檔") {
                model.openMainWindow?()
                model.searchFocus += 1
            }
            .keyboardShortcut("f")
        }
        CommandGroup(after: .sidebar) {
            ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, section in
                Button(section.title) { model.section = section }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
            }
            Divider()
            Button(model.showInspector ? "隱藏聲音與模型" : "顯示聲音與模型") {
                model.section = .studio
                model.showInspector.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            Divider()
        }
        CommandMenu("語音") {
            Button(model.compareTargets.isEmpty ? "產生音檔" : "比較 \(model.compareTargets.count) 個模型") {
                model.generateTask()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!model.canGenerate)
            Button("取消所有工作") { model.cancelAll() }
                .keyboardShortcut(".")
                .disabled(model.activeJobs.isEmpty)
            Divider()
            Button(model.player.isPlaying ? "暫停" : "播放") { model.togglePlay() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(model.player.current == nil && model.selectedItem == nil)
            Button("顯示詳情") { if let item = model.selectedItem { model.showDetail(item) } }
                .keyboardShortcut("i")
                .disabled(model.selectedItem == nil)
            Button("用這份稿子") { if let item = model.selectedItem { model.reuse(item) } }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(model.selectedItem == nil)
            Button("存成聲音…") { model.saveVoiceItem = model.selectedItem }
                .disabled(model.selectedItem == nil)
            Button("在 Finder 中顯示") { model.reveal(model.selectedItems) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.selection.isEmpty)
            Divider()
            Button("重新整理") { Task { await model.refresh() } }
                .keyboardShortcut("r")
            Button("重新啟動語音服務") { Task { await model.restartService() } }
        }
    }
}

struct MenuBarContent: View {
    @Environment(StudioModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.activeJobs.isEmpty ? model.serviceText : "產生中：\(model.activeJobs.count) 個工作")
        Divider()
        Button("打開九官鳥") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("唸出剪貼簿的文字") {
            if let text = NSPasteboard.general.string(forType: .string) {
                model.receive(text: text)
                openWindow(id: "main")
            }
        }
        if !model.activeJobs.isEmpty {
            Button("取消所有工作") { model.cancelAll() }
        }
        Divider()
        Button("結束九官鳥") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
