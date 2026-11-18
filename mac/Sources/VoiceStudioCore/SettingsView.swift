import AppKit
import ServiceManagement
import SwiftUI

/// 設定的每一頁：側欄的順序、分組、圖示、搜尋用的關鍵字。
enum SettingsPage: String, CaseIterable, Identifiable {
    case generate, pronounce, models, general, ai, status

    var id: String { rawValue }
    static let storageKey = "settingsPage"
    static let windowID = "settings"

    var title: String {
        switch self {
        case .generate: "產生"
        case .pronounce: "發音字典"
        case .models: "模型與記憶體"
        case .general: "一般"
        case .ai: "AI 工具"
        case .status: "檢查與狀態"
        }
    }

    var symbol: String {
        switch self {
        case .generate: "waveform"
        case .pronounce: "character.book.closed.fill"
        case .models: "internaldrive.fill"
        case .general: "gearshape.fill"
        case .ai: "puzzlepiece.extension.fill"
        case .status: "checkmark.seal.fill"
        }
    }

    var color: Color {
        switch self {
        case .generate: IconTint.persimmon
        case .pronounce: IconTint.brown
        case .models: IconTint.blue
        case .general: IconTint.gray
        case .ai: IconTint.indigo
        case .status: IconTint.green
        }
    }

    /// 側欄的分組（組和組之間空一點）
    static let groups: [[SettingsPage]] = [[.generate, .pronounce], [.models], [.general, .ai, .status]]

    /// 搜尋用：那一頁項目的名稱，加上常用的說法
    var keywords: [String] {
        switch self {
        case .generate: ["預設模型", "預設聲音", "仿聲", "配音員", "聲音描述", "自動播放", "邊產生邊播", "完成", "Dock"]
        case .pronounce: ["唸錯", "讀音", "寫法", "專有名詞"]
        case .models: ["記憶體上限", "卸載", "載入", "儲存空間", "模型資料夾", "下載", "GB"]
        case .general: ["登入時自動打開", "開機", "資料夾", "資料位置"]
        case .ai: ["MCP", "Claude", "Claude Code", "位址", "指令", "工具", "synthesize", "speak", "唸出來", "出聲", "通知"]
        case .status: ["語音服務", "重新啟動", "紀錄檔", "ffmpeg", "語速", "版本", "環境檢查"]
        }
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || ([title] + keywords).contains { $0.localizedCaseInsensitiveContains(q) }
    }
}

/// 設定視窗：左邊側欄（可搜尋、記得上次的頁面），右邊那一頁。
struct SettingsView: View {
    @AppStorage(SettingsPage.storageKey) private var stored = SettingsPage.generate.rawValue
    @State private var query = ""
    @FocusState private var searching: Bool

    private var page: SettingsPage { SettingsPage(rawValue: stored) ?? .generate }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                SidebarSearchField(prompt: "搜尋設定", text: $query, focused: $searching)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(SettingsPage.groups.enumerated()), id: \.offset) { index, group in
                            let pages = group.filter { $0.matches(query) }
                            if !pages.isEmpty {
                                if index > 0 { Spacer().frame(height: 10) }
                                ForEach(pages) { item in
                                    SettingsRow(page: item, selected: item == page) { stored = item.rawValue }
                                }
                            }
                        }
                        if SettingsPage.allCases.allSatisfy({ !$0.matches(query) }) {
                            Text("找不到「\(query)」")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(8)
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 220, max: 260)
            .frame(minWidth: 210)   // 欄寬在設定視窗第一次打開時有時不生效，內容自己也要撐開
            .toolbar(removing: .sidebarToggle)
            .onChange(of: query) { _, value in
                // 只剩一頁時直接選它
                let found = SettingsPage.allCases.filter { $0.matches(value) }
                if !value.isEmpty, found.count == 1, let only = found.first { stored = only.rawValue }
            }
        } detail: {
            SettingsPageView(page: page)
                .navigationTitle(page.title)
        }
        .frame(minWidth: 700, idealWidth: 820, minHeight: 460, idealHeight: 580)
        .tint(Color.persimmon)
    }
}

/// 側欄的一列：彩色圓角方塊加白色符號，選到的是灰底。
struct SettingsRow: View {
    let page: SettingsPage
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: page.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(page.color.gradient))
                    .accessibilityHidden(true)
                Text(page.title)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rowBackground(selected: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SettingsPageView: View {
    let page: SettingsPage

    var body: some View {
        switch page {
        case .generate: GenerateSettings()
        case .pronounce: PronounceSettings()
        case .models: MemorySettings()
        case .general: GeneralSettings()
        case .ai: AIToolSettings()
        case .status: StatusSettings()
        }
    }
}

// MARK: - 產生

struct GenerateSettings: View {
    @Environment(StudioModel.self) private var model
    @AppStorage("autoplay", store: AppDefaults.store) private var autoplay = true
    @AppStorage("bounceDock", store: AppDefaults.store) private var bounceDock = true

    var body: some View {
        Form {
            Section {
                ForEach(Mode.allCases) { mode in
                    Picker(mode.label, selection: Binding(
                        get: { model.settings?.defaultModel(for: mode) ?? "" },
                        set: { id in
                            if let m = model.models.first(where: { $0.id == id }) {
                                Task { await model.setDefault(m, for: mode) }
                            }
                        })) {
                        ForEach(model.models.filter { $0.modes.contains(mode) }) { m in
                            Text(m.isDownloaded ? m.name : "\(m.name)（未下載）").tag(m.id)
                        }
                    }
                }
            } header: {
                Text("預設模型")
            } footer: {
                Text("沒有特別指定模型時用這裡的設定；Claude 經 MCP 產生時也是。在「產生」頁選過的模型會優先。")
            }

            Section {
                Picker("預設聲音", selection: Binding(
                    get: { model.settings?.defaultVoice ?? "" },
                    set: { name in Task { await model.setDefaultVoice(name) } })) {
                    Text("聲音庫的第一個").tag("")
                    ForEach(model.voices) { Text($0.label).tag($0.name) }
                }
            } footer: {
                Text("AI 工具沒有指定聲音時用這一個。")
            }

            Section {
                Toggle("自動播放", isOn: $autoplay)
                Toggle("九官鳥在背景時，讓 Dock 圖示跳一下", isOn: $bounceDock)
            } header: {
                Text("產生完成後")
            } footer: {
                Text("稿子有兩段以上時，自動播放會從第一段做好就開始播，不用等整份做完。")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 發音字典

struct PronounceRule: Identifiable, Equatable {
    let id = UUID()
    var written = ""
    var spoken = ""
}

struct PronounceSettings: View {
    @Environment(StudioModel.self) private var model
    @State private var rules: [PronounceRule] = []
    @State private var saved: [PronounceRule] = []
    @State private var selection: PronounceRule.ID?
    @State private var status = ""

    private var dirty: Bool {
        rules.map { [$0.written, $0.spoken] } != saved.map { [$0.written, $0.spoken] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("模型唸錯的字詞，可以指定另一種寫法來唸。稿子不用改，音檔的詳情裡看得到實際唸的文字。")
                .foregroundStyle(.secondary)
            Table($rules, selection: $selection) {
                TableColumn("稿子裡的寫法") { $rule in
                    TextField("例：山嵐", text: $rule.written).labelsHidden()
                }
                TableColumn("要唸成") { $rule in
                    TextField("例：山藍", text: $rule.spoken).labelsHidden()
                }
            }
            .onDeleteCommand(perform: remove)
            HStack(spacing: 4) {
                Button {
                    let rule = PronounceRule()
                    rules.append(rule)
                    selection = rule.id
                } label: {
                    Image(systemName: "plus")
                }
                .help("新增一組")
                .accessibilityLabel("新增一組")
                Button(action: remove) {
                    Image(systemName: "minus")
                }
                .disabled(selection == nil)
                .help("移除選取的那組")
                .accessibilityLabel("移除選取的那組")
                Text(dirty ? "有還沒儲存的變更" : status)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
                Spacer()
                Button("儲存") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s")
                    .disabled(!dirty)
            }
        }
        .padding(20)
        .task {
            let loaded = (try? await model.client.pronounceRules()) ?? []
            rules = loaded.compactMap { $0.count == 2 ? PronounceRule(written: $0[0], spoken: $0[1]) : nil }
            saved = rules
        }
    }

    private func remove() {
        rules.removeAll { $0.id == selection }
        selection = nil
    }

    private func save() {
        let payload = rules
            .map { [$0.written.trimmingCharacters(in: .whitespaces), $0.spoken.trimmingCharacters(in: .whitespaces)] }
            .filter { !$0[0].isEmpty }
        Task {
            do {
                let n = try await model.client.savePronounceRules(payload)
                rules.removeAll { $0.written.trimmingCharacters(in: .whitespaces).isEmpty }
                saved = rules
                status = "已儲存 \(n) 組"
            } catch {
                status = "儲存失敗：\(error.localizedDescription)"
            }
        }
    }
}

// MARK: - 模型與記憶體

struct MemorySettings: View {
    @Environment(StudioModel.self) private var model
    @State private var budget = 16.0

    var body: some View {
        let downloaded = model.models.filter(\.isDownloaded)
        let loaded = model.models.filter(\.loaded)
        Form {
            Section {
                LabeledContent("記憶體上限") {
                    HStack {
                        Slider(value: $budget, in: 4...40, step: 2) { editing in
                            if !editing { Task { await model.setMemoryBudget(budget) } }
                        }
                        .frame(maxWidth: 240)
                        .accessibilityLabel("記憶體上限")
                        Text(String(format: "%.0f GB", budget))
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }
                }
                LabeledContent("目前載入") {
                    Text(loaded.isEmpty ? "沒有" : "\(loaded.map(\.name).joined(separator: "、"))（約 \(String(format: "%.1f", model.loadedGB)) GB）")
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("記憶體")
            } footer: {
                Text("留在記憶體裡的模型超過上限時，最久沒用的會自動卸載。上限越高，換模型越不用等；產生時用到的模型會自動載入。")
            }

            Section("儲存空間") {
                LabeledContent("已下載的模型",
                               value: "\(downloaded.count) 個，共 \(Formatting.size(gb: downloaded.map(\.sizeGb).reduce(0, +)))")
                LabeledContent("模型資料夾") {
                    Button("在 Finder 中打開") { model.revealModelCache() }
                }
                LabeledContent("下載、刪除、加入模型") {
                    Button("打開「模型」") {
                        model.section = .models
                        model.openMainWindow?()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { budget = model.settings?.memoryBudgetGb ?? 16 }
    }
}

// MARK: - 一般

struct GeneralSettings: View {
    @Environment(StudioModel.self) private var model
    // 未打包（swift run）時沒有 bundle，登入項目用不了
    private let canLogin = Bundle.main.bundleIdentifier != nil
    @State private var launchAtLogin = false
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("登入時自動打開", isOn: $launchAtLogin)
                    .disabled(!canLogin)
                    .onChange(of: launchAtLogin) {
                        guard canLogin, launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
                        do {
                            if launchAtLogin { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            } footer: {
                Text("九官鳥開著，Claude 才能經 MCP 產生語音。關掉視窗不會結束，選單列的圖示還在；要完全結束按 ⌘Q。")
            }

            Section("資料") {
                LabeledContent("音檔、聲音庫、發音字典") {
                    Button("在 Finder 中打開") { NSWorkspace.shared.open(model.supervisor.home) }
                }
                Text("稿子、錄音、成品都只存在這台 Mac 上；只有下載模型時會連到 Hugging Face。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if canLogin { launchAtLogin = SMAppService.mainApp.status == .enabled }
        }
    }
}

// MARK: - AI 工具

struct AIToolSettings: View {
    @Environment(StudioModel.self) private var model
    @State private var copied: String?

    private var mcpURL: String { "http://localhost:\(model.supervisor.port)/mcp" }
    private var claudeCommand: String { "claude mcp add --transport http myna \(mcpURL)" }

    private func copyButton(_ text: String) -> some View {
        Button(copied == text ? "已拷貝" : "拷貝") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = text
        }
    }

    private let tools: [(String, String)] = [
        ("list_voices", "列出可用的聲音"),
        ("list_models", "列出已下載的模型與能力"),
        ("synthesize", "把文字唸成音檔，可以指定聲音與模型"),
        ("speak", "把文字直接從這台 Mac 唸出來"),
        ("get_job", "查產生的進度、取回結果"),
        ("add_voice", "用一段錄音新增仿聲的聲音"),
        ("list_recent", "最近產生的音檔"),
    ]

    var body: some View {
        Form {
            Section {
                LabeledContent("MCP 位址") {
                    HStack {
                        Text(mcpURL).textSelection(.enabled).monospaced()
                        copyButton(mcpURL)
                    }
                }
                LabeledContent("狀態", value: model.supervisor.isRunning ? "可以連線" : model.serviceText)
            } header: {
                Text("讓 AI 工具用九官鳥產生語音")
            } footer: {
                Text("九官鳥開著時，Claude 這類支援 MCP 的工具可以連到這個位址。這個位址只有這台 Mac 自己連得到。")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(claudeCommand)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                    copyButton(claudeCommand)
                }
            } header: {
                Text("加到 Claude Code")
            } footer: {
                Text("在終端機貼上這一行，重開 Claude Code 後就能叫它用九官鳥唸稿。其他支援 MCP 的工具，把上面的位址填進它的設定。")
            }

            Section {
                Toggle("讓 AI 工具直接唸出來", isOn: Binding(
                    get: { model.settings?.allowSpeak ?? true },
                    set: { on in Task { await model.setAllowSpeak(on) } }))
            } footer: {
                Text("打開時，AI 工具可以叫九官鳥把一句話直接播出來，例如事情做完通知你一聲。唸過的內容會留在「音檔」。關掉之後 AI 工具還是能產生音檔，只是不會自己出聲。")
            }

            Section("AI 工具能做的事") {
                ForEach(tools, id: \.0) { tool in
                    LabeledContent {
                        Text(tool.1).foregroundStyle(.secondary)
                    } label: {
                        Text(tool.0).monospaced()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 檢查與狀態

struct StatusSettings: View {
    @Environment(StudioModel.self) private var model

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "開發版"
    }

    var body: some View {
        Form {
            Section("語音服務") {
                check(model.supervisor.isRunning, "語音服務", model.serviceText)
                check(model.hasDownloadedModels, "模型",
                      model.hasDownloadedModels ? "已下載 \(model.models.filter(\.isDownloaded).count) 個" : "還沒有下載任何模型")
                check(model.ffmpeg, "ffmpeg（選配）",
                      model.ffmpeg ? "有，所有模型都能調語速" : "沒有：只有 OmniVoice 能調語速，其他模型固定 1.00×")
            }

            Section {
                LabeledContent("紀錄檔") {
                    Button("打開") { NSWorkspace.shared.open(model.supervisor.logURL) }
                }
                LabeledContent("語音服務沒反應時") {
                    Button("重新啟動語音服務") { Task { await model.restartService() } }
                }
            }

            Section {
                LabeledContent("版本", value: version)
                if let licenses = Bundle.main.url(forResource: "ThirdPartyLicenses", withExtension: "txt") {
                    LabeledContent("用到的開源軟體") {
                        Button("看授權條款") { NSWorkspace.shared.open(licenses) }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func check(_ ok: Bool, _ title: String, _ detail: String) -> some View {
        LabeledContent {
            Text(detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(ok ? Color.green : Color.signal)
                    .accessibilityLabel(ok ? "正常" : "要注意")
            }
        }
    }
}
