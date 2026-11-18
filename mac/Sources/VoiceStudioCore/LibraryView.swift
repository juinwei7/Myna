import AppKit
import SwiftUI

/// 「音檔」：所有產生過的音檔。表格可排序、多選；點開一筆是它的詳情。
struct LibraryView: View {
    @Environment(StudioModel.self) private var model

    var body: some View {
        if let item = model.item(model.detailItem) {
            AudioDetailView(item: item)
        } else {
            LibraryTable()
        }
    }
}

struct LibraryTable: View {
    @Environment(StudioModel.self) private var model
    @Environment(\.undoManager) private var undo
    @State private var sortOrder = [KeyPathComparator(\HistoryItem.created, order: .reverse)]

    private var items: [HistoryItem] {
        let search = model.search
        let base = search.isEmpty ? model.history : model.history.filter {
            $0.text.localizedCaseInsensitiveContains(search)
                || $0.voiceLabel.localizedCaseInsensitiveContains(search)
                || $0.modelName.localizedCaseInsensitiveContains(search)
        }
        return base.sorted(using: sortOrder)
    }

    var body: some View {
        @Bindable var model = model
        Table(of: HistoryItem.self, selection: $model.selection, sortOrder: $sortOrder) {
            TableColumn("稿子", value: \.text) { item in
                HStack(spacing: 6) {
                    if model.player.isPlaying(item.id) {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(Color.persimmon)
                            .accessibilityLabel("播放中")
                    }
                    Text(item.preview).lineLimit(1)
                }
            }
            .width(min: 180, ideal: 360)
            TableColumn("聲音", value: \.voiceLabel)
                .width(min: 70, ideal: 110)
            TableColumn("模型", value: \.modelName) { item in
                HStack(spacing: 5) {
                    Text(item.modelName).lineLimit(1)
                    if item.batch != nil { Chip(text: "比較", tint: .persimmon) }
                }
            }
            .width(min: 110, ideal: 190)
            TableColumn("長度", value: \.seconds) { item in
                Text(Formatting.duration(item.seconds)).monospacedDigit()
            }
            .width(min: 56, ideal: 70)
            TableColumn("時間", value: \.created) { item in
                Text(Formatting.time(item.created)).monospacedDigit()
            }
            .width(min: 70, ideal: 96)
        } rows: {
            ForEach(items) { item in
                TableRow(item)
                    .itemProvider { NSItemProvider(contentsOf: item.fileURL) }
            }
        }
        .contextMenu(forSelectionType: HistoryItem.ID.self) { ids in
            HistoryMenu(model: model, items: model.history.filter { ids.contains($0.id) }, undo: undo)
        } primaryAction: { ids in
            if let item = model.item(ids.first) { model.showDetail(item) }
        }
        .onDeleteCommand { Task { await model.delete(model.selectedItems, undo: undo) } }
        .onKeyPress(.space) {
            model.togglePlay()
            return .handled
        }
        .overlay {
            if model.history.isEmpty && model.loaded {
                ContentUnavailableView("還沒有音檔", systemImage: "waveform",
                                       description: Text("到「產生」寫稿子，做出來的音檔都會留在這裡"))
            } else if items.isEmpty && !model.search.isEmpty {
                ContentUnavailableView.search(text: model.search)
            }
        }
        .navigationTitle("音檔")
        .navigationSubtitle(model.selection.count > 1 ? "已選取 \(model.selection.count) 個"
                            : (model.search.isEmpty ? "\(model.history.count) 個" : "找到 \(items.count) 個"))
        .toolbar {
            ToolbarItem {
                Button { if let item = model.selectedItem { model.showDetail(item) } } label: {
                    Label("顯示詳情", systemImage: "info.circle")
                }
                .disabled(model.selectedItem == nil)
                .help("顯示選取音檔的詳情（也可以按兩下）")
            }
            ToolbarItem {
                Button { model.reveal(model.selectedItems) } label: {
                    Label("在 Finder 中顯示", systemImage: "folder")
                }
                .disabled(model.selection.isEmpty)
                .help("在 Finder 中顯示選取的音檔（⇧⌘R）")
            }
            ToolbarItem {
                Button { Task { await model.delete(model.selectedItems, undo: undo) } } label: {
                    Label("丟到垃圾桶", systemImage: "trash")
                }
                .disabled(model.selection.isEmpty)
                .help("把選取的音檔丟到垃圾桶（可以用 ⌘Z 復原）")
            }
            SettingsToolbarItem()
        }
    }
}

/// 一個音檔的詳情：像一份文件，標題、基本資料、動作、同一批的其他版本、稿子全文。
struct AudioDetailView: View {
    @Environment(StudioModel.self) private var model
    @Environment(\.undoManager) private var undo
    let item: HistoryItem

    /// 這份稿子的所有版本（稿子一字不差），新的在前
    private var siblings: [HistoryItem] {
        model.history.filter { $0.text == item.text }
    }

    private var title: String {
        let first = item.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? item.text
        return first.count > 28 ? String(first.prefix(28)) + "…" : first
    }

    var body: some View {
        let playing = model.player.isPlaying(item.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.songti(26))
                    .textSelection(.enabled)

                HStack(spacing: 16) {
                    Label(item.voiceLabel, systemImage: item.mode.symbol)
                    Text(item.modelName)
                    Text(Formatting.duration(item.seconds)).monospacedDigit()
                    Text(Formatting.time(item.created)).monospacedDigit()
                    if abs(item.speed - 1) > 0.01 {
                        Text(String(format: "語速 %.2f×", item.speed)).monospacedDigit()
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.top, 8)

                HStack(spacing: 20) {
                    LinkAction(playing ? "暫停" : "播放", systemImage: playing ? "pause.fill" : "play.fill") {
                        model.player.toggle(item.playable)
                    }
                    LinkAction("用這份稿子", systemImage: "square.and.pencil") { model.reuse(item) }
                    LinkAction("存成聲音", systemImage: "person.crop.circle.badge.plus") { model.saveVoiceItem = item }
                    LinkAction("在 Finder 中顯示", systemImage: "folder") { model.reveal([item]) }
                    ShareLink(item: item.fileURL) { Label("分享", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.persimmon)
                }
                .padding(.top, 14)

                Divider().padding(.vertical, 22)

                if siblings.count > 1 {
                    HStack(alignment: .firstTextBaseline) {
                        SectionTitle("這份稿子的版本")
                        Text("\(siblings.count) 個")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 2) {
                        ForEach(siblings) { other in
                            SiblingRow(item: other, current: other.id == item.id)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 26)
                    .padding(.horizontal, -8)
                }

                SectionTitle("稿子")
                Text(item.text)
                    .font(.system(size: 15))
                    .lineSpacing(7)
                    .textSelection(.enabled)
                    .padding(.top, 10)

                if item.spoken != item.text {
                    SectionTitle("實際唸的文字")
                        .padding(.top, 26)
                    Text("發音字典把幾個字換成別的寫法來唸。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    Text(item.spoken)
                        .font(.system(size: 15))
                        .lineSpacing(7)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.top, 8)
                }

                if !item.instruct.isEmpty {
                    SectionTitle(item.mode == .design ? "聲音描述" : "語氣")
                        .padding(.top, 26)
                    Text(item.instruct)
                        .font(.system(size: 15))
                        .textSelection(.enabled)
                        .padding(.top, 10)
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .navigationTitle("音檔")
        .navigationSubtitle(item.file)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { model.detailItem = nil } label: {
                    Label("所有音檔", systemImage: "chevron.backward")
                }
                .help("回到所有音檔")
            }
            ToolbarItem {
                Button { Task { await model.delete([item], undo: undo) } } label: {
                    Label("丟到垃圾桶", systemImage: "trash")
                }
                .help("把這個音檔丟到垃圾桶（可以用 ⌘Z 復原）")
            }
            SettingsToolbarItem()
        }
    }
}

/// 這份稿子的一個版本：按一下試聽，目前看的那筆有標記。
struct SiblingRow: View {
    @Environment(StudioModel.self) private var model
    let item: HistoryItem
    let current: Bool

    var body: some View {
        let playing = model.player.isPlaying(item.id)
        HStack(spacing: 10) {
            Button { model.player.toggle(item.playable) } label: {
                HStack(spacing: 10) {
                    Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(playing ? AnyShapeStyle(Color.persimmon) : AnyShapeStyle(.secondary))
                        .accessibilityHidden(true)
                    Text(item.modelName)
                        .fontWeight(current ? .semibold : .regular)
                    Text("\(item.voiceLabel)　\(Formatting.time(item.created))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if current { Chip(text: "目前這筆") }
                    Spacer()
                    Text(Formatting.duration(item.seconds))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(playing ? "暫停" : "播放")：\(item.modelName)")
            if !current {
                LinkAction("看這筆", systemImage: "arrow.right") { model.showDetail(item) }
                    .font(.callout)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .rowBackground(selected: current)
    }
}
