import AppKit
import SwiftUI

/// 主視窗：單色側欄＋各區域＋底部播放列。
struct RootView: View {
    @Environment(StudioModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            VStack(spacing: 0) {
                Group {
                    switch model.section {
                    case .studio: StudioView()
                    case .library: LibraryView()
                    case .voices: VoicesView()
                    case .models: ModelsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if model.player.current != nil {
                    Divider()
                    PlayerBar()
                }
            }
        }
        .tint(Color.persimmon)
        .sheet(isPresented: $model.showAddVoice) { AddVoiceSheet(pickedFile: model.addVoiceFile).tint(Color.persimmon) }
        .sheet(item: $model.saveVoiceItem) { SaveVoiceSheet(item: $0).tint(Color.persimmon) }
        .sheet(isPresented: $model.showAddModel) { AddModelSheet().tint(Color.persimmon) }
        .overlay { ServiceOverlay() }
        .onAppear {
            model.openMainWindow = { openWindow(id: "main") }
            // 截圖驗收用：`-openSettings YES` 直接開偏好設定
            if UserDefaults.standard.bool(forKey: "openSettings") { openWindow(id: SettingsPage.windowID) }
        }
        .onChange(of: model.text) { model.persist() }
        .onChange(of: model.mode) { model.persist() }
        .onChange(of: model.voiceName) { model.persist() }
        .onChange(of: model.speaker) { model.persist() }
        .onChange(of: model.modelChoice) { model.persist() }
        .onChange(of: model.design) { model.persist() }
        .onChange(of: model.showInspector) { model.persist() }
        .onChange(of: model.section) {
            // 聲音與模型可能被 Claude（經 MCP）或其他視窗改過，切過來時重讀
            Task { await model.refresh() }
        }
    }
}

// MARK: - 側欄

/// 側欄不用 List：系統的側欄清單會拿強調色畫圖示與選取列，這裡要的是單色。
/// 列是自己畫的按鈕，所以也沒有「清單裡放按鈕會讓點擊延遲」的問題。
struct Sidebar: View {
    @Environment(StudioModel.self) private var model
    @Environment(\.undoManager) private var undo
    @FocusState private var searching: Bool

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            SidebarSearchField(prompt: "搜尋所有音檔", text: $model.search, focused: $searching)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(AppSection.allCases) { section in
                        SidebarRow(title: section.title, symbol: section.symbol, count: count(section),
                                   selected: model.section == section && (section != .library || model.detailItem == nil)) {
                            model.detailItem = nil
                            model.section = section
                        }
                    }

                    if !model.history.isEmpty {
                        Text("最近的稿子")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.top, 18)
                            .padding(.bottom, 4)
                        // 同一份稿子試了幾個版本都只列一次，點進去看得到全部
                        ForEach(model.recentScripts) { script in
                            let item = script.latest
                            RecentRow(script: script,
                                      selected: model.section == .library
                                          && model.item(model.detailItem)?.text == item.text) {
                                model.showDetail(item)
                            }
                            .contextMenu { HistoryMenu(model: model, items: [item], undo: undo) }
                            .onDrag { NSItemProvider(contentsOf: item.fileURL) ?? NSItemProvider() }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }

            Divider()
            ActivityFooter()
        }
        .onChange(of: model.search) {
            if !model.search.isEmpty {
                model.detailItem = nil
                model.section = .library
            }
        }
        .onChange(of: model.searchFocus) { searching = true }
    }

    private func count(_ section: AppSection) -> Int {
        switch section {
        case .studio: model.activeJobs.count
        case .library: model.history.count
        case .voices: model.voices.count
        case .models: model.models.filter(\.isDownloaded).count
        }
    }
}

struct SidebarRow: View {
    let title: String
    let symbol: String
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text(title)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 14))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rowBackground(selected: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct RecentRow: View {
    @Environment(StudioModel.self) private var model
    let script: RecentScript
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let item = script.latest
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if model.player.isPlaying, model.item(model.player.current?.id)?.text == item.text {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.caption)
                            .foregroundStyle(Color.persimmon)
                            .accessibilityLabel("播放中")
                    }
                    Text(item.preview)
                        .lineLimit(1)
                }
                Text("\(Formatting.time(item.created))　\(script.count > 1 ? "\(script.count) 個版本" : item.modelName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rowBackground(selected: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 側欄底部：服務狀態、進行中的工作與下載，右邊是匯入稿子。
struct ActivityFooter: View {
    @Environment(StudioModel.self) private var model

    private var downloading: [ModelInfo] { model.models.filter(\.isDownloading) }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                if let job = model.activeJobs.first {
                    busy(model.activeJobs.count > 1 ? "產生中，另有 \(model.activeJobs.count - 1) 個" : job.stage)
                }
                ForEach(downloading) { m in
                    busy("下載 \(m.name) \(Formatting.percent(m.progress))")
                }
                if model.activeJobs.isEmpty && downloading.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(model.supervisor.isRunning ? Color.green : Color.signal)
                            .accessibilityHidden(true)
                        Text(model.supervisor.isRunning ? "已就緒" : model.serviceText)
                            .lineLimit(2)
                    }
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button { model.importScript() } label: {
                Label("匯入", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("匯入文字檔當稿子（⌘O）")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func busy(_ text: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text(text).lineLimit(1)
        }
    }
}

/// 服務還沒起來或掛掉時蓋在視窗上。
struct ServiceOverlay: View {
    @Environment(StudioModel.self) private var model

    var body: some View {
        switch model.supervisor.state {
        case .starting:
            ProgressView("正在啟動語音服務…")
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        case .failed(let why):
            ContentUnavailableView {
                Label("語音服務沒有在跑", systemImage: "exclamationmark.triangle")
            } description: {
                Text(why)
            } actions: {
                Button("重新啟動") { Task { await model.restartService() } }
                    .buttonStyle(.borderedProminent)
                Button("打開紀錄檔") { NSWorkspace.shared.open(model.supervisor.logURL) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial)
        default:
            EmptyView()
        }
    }
}
