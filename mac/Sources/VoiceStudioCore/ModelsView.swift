import AppKit
import SwiftUI

/// 「模型」：目錄、下載、載入狀態。
struct ModelsView: View {
    @Environment(StudioModel.self) private var model

    private var downloaded: [ModelInfo] { model.models.filter(\.isDownloaded) }
    private var others: [ModelInfo] { model.models.filter { !$0.isDownloaded } }

    var body: some View {
        @Bindable var model = model
        List {
            Section {
                MemoryGauge()
            }
            if !downloaded.isEmpty {
                Section("已下載") {
                    ForEach(downloaded) { ModelRow(info: $0) }
                }
            }
            if !others.isEmpty {
                Section("可下載") {
                    ForEach(others) { ModelRow(info: $0) }
                }
            }
        }
        .listStyle(.inset)
        .navigationTitle("模型")
        .navigationSubtitle("已下載 \(downloaded.count) 個，共 \(Formatting.size(gb: downloaded.map(\.sizeGb).reduce(0, +)))")
        .toolbar {
            ToolbarItem {
                Button { model.revealModelCache() } label: {
                    Label("模型資料夾", systemImage: "folder")
                }
                .help("在 Finder 打開模型存放的資料夾")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { model.showAddModel = true } label: {
                    Label("加入模型", systemImage: "plus")
                }
                .help("用 Hugging Face 上的模型名稱加入自訂模型")
            }
            SettingsToolbarItem()
        }
        // 刪除模型檔案不能復原（要重新下載），所以這裡才用確認對話框（憲法 U3）
        .confirmationDialog("刪除「\(model.modelToDelete?.name ?? "")」的模型檔案？",
                            isPresented: Binding(get: { model.modelToDelete != nil },
                                                 set: { if !$0 { model.modelToDelete = nil } }),
                            presenting: model.modelToDelete) { target in
            Button("刪除", role: .destructive) { Task { await model.deleteModel(target) } }
            Button("取消", role: .cancel) {}
        } message: { target in
            Text("會釋出約 \(Formatting.size(gb: target.sizeGb)) 的空間。之後要用得重新下載。")
        }
    }
}

struct MemoryGauge: View {
    @Environment(StudioModel.self) private var model

    var body: some View {
        let budget = model.settings?.memoryBudgetGb ?? 16
        let loaded = model.models.filter(\.loaded)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("記憶體", systemImage: "memorychip")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.primary)
                Spacer()
                Text(String(format: "約 %.1f／%.0f GB", model.loadedGB, budget))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(model.loadedGB, budget), total: budget)
                .accessibilityLabel("已載入模型佔用的記憶體")
            Text(loaded.isEmpty ? "目前沒有載入任何模型；產生時會自動載入。"
                 : "已載入：\(loaded.map(\.name).joined(separator: "、"))。超過上限時，最久沒用的會自動卸載。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct ModelRow: View {
    @Environment(StudioModel.self) private var model
    let info: ModelInfo

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(info.name)
                        .font(.songti(17))
                    if info.recommended { Chip(text: "推薦", tint: .persimmon) }
                    if info.custom { Chip(text: "自訂") }
                    ForEach(info.defaultFor) { Chip(text: "\($0.label)預設", tint: .green) }
                }
                Text(info.summary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ForEach(info.modes) { Chip(text: $0.label) }
                    if !info.commercial {
                        Chip(text: "不可商用", tint: .signal)
                    }
                    Text("\(Formatting.size(gb: info.sizeGb)) · \(info.license) · \(Formatting.langs(info.langs))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !info.notes.isEmpty {
                    Text(info.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = info.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Spacer(minLength: 12)
            control
                .frame(minWidth: 150, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .contextMenu { menuItems }
    }

    @ViewBuilder private var control: some View {
        if info.isDownloading {
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 3) {
                    ProgressView(value: info.progress ?? 0)
                        .frame(width: 120)
                        .accessibilityLabel("\(info.name)的下載進度")
                    Text(progressText)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Button { Task { await model.cancelDownload(info) } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("取消下載（已下載的部分會留著，下次接著下載）")
                .accessibilityLabel("取消下載")
            }
        } else if info.isDownloaded {
            HStack(spacing: 8) {
                if info.loading {
                    ProgressView().controlSize(.small)
                    Text("載入中").font(.caption).foregroundStyle(.secondary)
                } else if info.loaded {
                    Label("已載入", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Menu {
                    menuItems
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("更多動作")
                .accessibilityLabel("\(info.name)的更多動作")
            }
        } else {
            Button(info.downloadedBytes > 0 ? "繼續下載" : "下載") { Task { await model.download(info) } }
                .help("下載 \(Formatting.size(gb: info.sizeGb))")
        }
    }

    private var progressText: String {
        guard let total = info.totalBytes, total > 0 else { return "準備中…" }
        return "\(Formatting.bytes(info.downloadedBytes))／\(Formatting.bytes(total))"
    }

    @ViewBuilder private var menuItems: some View {
        if info.isDownloaded {
            if info.loaded {
                Button("從記憶體卸載") { Task { await model.unload(info) } }
            } else {
                Button("載入記憶體") { Task { await model.load(info) } }
                    .disabled(info.loading)
            }
            Divider()
            ForEach(info.modes) { mode in
                Button("設為「\(mode.label)」的預設模型") { Task { await model.setDefault(info, for: mode) } }
                    .disabled(info.defaultFor.contains(mode))
            }
            Divider()
            Button("打開 Hugging Face 頁面") { openPage() }
            Button("刪除模型檔案…", role: .destructive) { model.modelToDelete = info }
        } else {
            if info.isDownloading {
                Button("取消下載") { Task { await model.cancelDownload(info) } }
            } else {
                Button("下載") { Task { await model.download(info) } }
            }
            Button("打開 Hugging Face 頁面") { openPage() }
            if info.custom || info.downloadedBytes > 0 {
                Divider()
                Button(info.custom ? "移除這個自訂模型…" : "刪除已下載的部分…", role: .destructive) {
                    model.modelToDelete = info
                }
            }
        }
    }

    private func openPage() {
        if let url = URL(string: "https://huggingface.co/\(info.repo)") { NSWorkspace.shared.open(url) }
    }
}

/// 加入自訂模型：輸入 Hugging Face 上的模型名稱。
struct AddModelSheet: View {
    @Environment(StudioModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var repo = ""
    @State private var working = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("加入模型").font(.title2.weight(.semibold))
            Text("輸入 Hugging Face 上 MLX 格式的模型名稱。目前支援 Qwen3-TTS、Breeze-TTS、VoxCPM2、OmniVoice、MOSS-TTS Nano 系列的其他版本（例如比較小的量化版）。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("模型名稱", text: $repo, prompt: Text("mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit"))
                .textFieldStyle(.roundedBorder)
                .onSubmit { add() }
            if let message {
                Text(message).font(.caption).foregroundStyle(.red)
            }
            HStack {
                if working { ProgressView().controlSize(.small) }
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("加入") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(working || repo.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 500)
    }

    private func add() {
        guard !working else { return }
        working = true
        message = nil
        Task {
            defer { working = false }
            do {
                _ = try await model.client.addCustomModel(repo: repo.trimmingCharacters(in: .whitespaces))
                await model.refresh()
                dismiss()
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
