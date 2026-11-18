import AppKit
import SwiftUI

/// 「產生」：稿子是主角，下面列出這份稿子試過的各個版本；右側檢閱器放聲音與模型的設定。
struct StudioView: View {
    @Environment(StudioModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.loaded && !model.hasDownloadedModels {
                NoModelsView()
            } else {
                VStack(spacing: 0) {
                    ScriptEditor()
                    StatusLine()
                    TakesPanel()
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .inspector(isPresented: $model.showInspector) {
            InspectorView()
                .inspectorColumnWidth(min: 270, ideal: 300, max: 400)
        }
        .navigationTitle("產生")
        .toolbar {
            // 切換內容的控制放工具列中間，側欄只當導覽
            ToolbarItem(placement: .principal) {
                Picker("方式", selection: $model.mode) {
                    ForEach(Mode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("仿聲：照參考錄音；配音員：內建的聲音；聲音描述：用文字形容想要的聲音")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { model.generateTask() } label: {
                    Label(model.compareTargets.isEmpty ? "產生音檔" : "比較 \(model.compareTargets.count) 個模型",
                          systemImage: "play.fill")
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderedProminent)
                .disabled(!model.canGenerate)
                .help(model.blocker ?? "產生音檔（⌘↩）")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { model.showInspector.toggle() } label: {
                    Label("聲音與模型", systemImage: "sidebar.trailing")
                }
                .help("顯示或隱藏聲音與模型的設定（⌥⌘I）")
            }
            SettingsToolbarItem()
        }
    }
}

/// 一個模型都還沒下載時的引導（Spec 002 C-3）：列出推薦的模型讓使用者自己挑，不替人決定下載哪一個。
struct NoModelsView: View {
    @Environment(StudioModel.self) private var model

    private var choices: [ModelInfo] { model.models.filter(\.recommended) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("先挑一個模型")
                    .font(.songti(26))
                Text("九官鳥要有至少一個語音模型才能產生聲音。模型只下載一次，之後都在這台 Mac 上離線運作；之後隨時可以再加、再刪。")
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                Divider().padding(.vertical, 18)
                ForEach(choices) { info in
                    ModelRow(info: info)
                    Divider()
                }
                LinkAction("看所有模型", systemImage: "shippingbox") { model.section = .models }
                    .padding(.top, 16)
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - 稿子

struct ScriptEditor: View {
    @Environment(StudioModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            if let selected = model.selectedModel, !selected.commercial {
                Banner(text: "\(selected.name) 只能用在研究與非商業用途，要商用的成品請換別的模型。")
                    .padding(.horizontal, 28)
                    .padding(.top, 16)
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.text)
                    .font(.system(size: 15))
                    .lineSpacing(7)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 27)
                    .padding(.vertical, 20)
                    .accessibilityLabel("稿子")
                if model.text.isEmpty {
                    Text("在這裡寫要唸的稿子。換行會分段唸、空一行會停久一點；也可以把文字檔拖進來。")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in model.loadScript(from: urls.first) }
        }
    }
}

/// 稿子下方的一行：狀態在左，字數與預估長度在右。
struct StatusLine: View {
    @Environment(StudioModel.self) private var model

    /// 中文旁白大約每秒 4.5 個字，給個粗估讓人知道稿子多長。
    private var estimate: String {
        let count = model.trimmedText.count
        guard count > 0 else { return "" }
        return "　約 " + Formatting.duration(Double(count) / 4.5 / model.speed)
    }

    var body: some View {
        HStack(spacing: 8) {
            // 還不能產生時，這裡直接說缺什麼（工具列的按鈕是灰的，要讓人知道為什麼）
            if !model.statusIsError, model.status.isEmpty, let blocker = model.blocker, model.loaded {
                Label(blocker, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(model.status)
                    .foregroundStyle(model.statusIsError ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .textSelection(.enabled)
                    .help(model.status)
            }
            Spacer()
            Text("\(model.trimmedText.count) 字\(estimate)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.callout)
        .padding(.horizontal, 32)
        .padding(.vertical, 8)
    }
}

// MARK: - 這份稿子的版本

/// 進行中的工作，加上跟目前稿子一字不差的產出。換模型、換聲音試出來的版本排在一起，方便逐一比較。
struct TakesPanel: View {
    @Environment(StudioModel.self) private var model
    @Environment(\.undoManager) private var undo

    var body: some View {
        let jobs = model.activeJobs
        let takes = model.takes
        if !jobs.isEmpty || !takes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    SectionTitle("這份稿子的版本")
                    if takes.count > 1 {
                        Text("\(takes.count) 個")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !jobs.isEmpty {
                        LinkAction("全部取消", systemImage: "xmark") { model.cancelAll() }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 6)
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(jobs) { JobRow(job: $0) }
                        ForEach(takes) { item in
                            TakeRow(item: item)
                                .contextMenu { HistoryMenu(model: model, items: [item], undo: undo) }
                                .onDrag { NSItemProvider(contentsOf: item.fileURL) ?? NSItemProvider() }
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .frame(maxHeight: min(CGFloat(jobs.count + takes.count) * 46 + 4, 236))
            }
            .padding(.bottom, 10)
        }
    }
}

// MARK: - 檢閱器

struct InspectorView: View {
    @Environment(StudioModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section(model.mode == .design ? "聲音描述" : (model.mode == .preset ? "配音員" : "聲音")) {
                switch model.mode {
                case .clone: cloneVoice
                case .preset: presetVoice
                case .design: designVoice
                }
            }

            Section("模型") { modelPicker }

            if model.showsInstruct {
                Section("語氣") {
                    TextField("語氣", text: $model.instruct, prompt: Text(model.selectedModel?.instructHint ?? ""),
                              axis: .vertical)
                        .lineLimit(1...3)
                        .labelsHidden()
                }
            }

            Section("語速") { speedControl }

            if model.usableModels.count >= 2 {
                Section {
                    Toggle("比較模型", isOn: $model.compareOn)
                    if model.compareOn {
                        ForEach(model.usableModels) { m in
                            Toggle(m.name, isOn: Binding(
                                get: { model.compareIDs.contains(m.id) },
                                set: { on in
                                    if on { model.compareIDs.insert(m.id) } else { model.compareIDs.remove(m.id) }
                                }))
                                .toggleStyle(.checkbox)
                        }
                    }
                } footer: {
                    if model.compareOn {
                        Text(model.compareTargets.isEmpty ? "至少勾兩個模型，同一份稿子會各產生一次。"
                             : "同一份稿子會用 \(model.compareTargets.count) 個模型各產生一次。")
                    }
                }
            }

        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var cloneVoice: some View {
        @Bindable var model = model
        if model.voices.isEmpty {
            Text("聲音庫還是空的").foregroundStyle(.secondary)
            Button("新增聲音…") { model.beginAddVoice() }
        } else {
            HStack {
                Picker("聲音", selection: $model.voiceName) {
                    ForEach(model.voices) { Text($0.label).tag($0.name) }
                }
                .labelsHidden()
                if let voice = model.currentVoice {
                    let playing = model.player.isPlaying(voice.playable.id)
                    Button { model.player.toggle(voice.playable) } label: {
                        Image(systemName: playing ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("試聽參考錄音")
                    .accessibilityLabel(playing ? "暫停試聽" : "試聽參考錄音")
                }
            }
            if let hint = model.currentVoice?.qualityHint {
                Label(hint, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Color.signal)
            }
        }
    }

    @ViewBuilder private var presetVoice: some View {
        @Bindable var model = model
        if model.speakers.isEmpty {
            Text("還沒有含配音員的模型").foregroundStyle(.secondary)
        } else {
            Picker("配音員", selection: $model.speaker) {
                ForEach(model.speakers) { Text("\($0.label)　\($0.note)").tag($0.id) }
            }
            .labelsHidden()
        }
    }

    @ViewBuilder private var designVoice: some View {
        @Bindable var model = model
        TextField("聲音描述", text: $model.design, prompt: Text(model.selectedModel?.designHint ?? ""),
                  axis: .vertical)
            .lineLimit(2...5)
            .labelsHidden()
        Text("每次產生的音色會略有不同。滿意的那次可以按右鍵「存成聲音」。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder private var modelPicker: some View {
        @Bindable var model = model
        if let selected = model.selectedModel {
            Picker("模型", selection: Binding(
                get: { selected.id },
                set: { model.modelChoice[model.mode.rawValue] = $0 })) {
                ForEach(model.usableModels) { Text($0.name).tag($0.id) }
            }
            .labelsHidden()
            Text(selected.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                if selected.commercial {
                    Chip(text: selected.license)
                } else {
                    Chip(text: "不可商用", tint: .signal)
                        .help(selected.license)
                }
                Chip(text: selected.sampleRate >= 48000 ? "48 kHz" : "24 kHz")
                if selected.loaded { Chip(text: "已載入", tint: .green) }
            }
        } else {
            Text("\(model.mode.label)還沒有可用的模型")
                .foregroundStyle(.secondary)
            Button("前往下載…") { model.section = .models }
        }
    }

    @ViewBuilder private var speedControl: some View {
        @Bindable var model = model
        HStack {
            // 「慢／快」放在滑桿外面：寫成滑桿自己的標籤會被主色染色
            Text("慢").font(.caption).foregroundStyle(.secondary)
            Slider(value: $model.speed, in: 0.7...1.3, step: 0.05) { Text("語速") }
                .labelsHidden()
                .disabled(!model.speedAvailable)
            Text("快").font(.caption).foregroundStyle(.secondary)
            Text(String(format: "%.2f×", model.speed))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)
        }
        if !model.speedAvailable {
            Text("這個模型調語速需要 ffmpeg；OmniVoice 可以直接調。")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if model.selectedModel?.nativeSpeed == true {
            Text("這個模型自己控制語速，不是事後變速。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
