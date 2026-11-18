import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 「聲音庫」：仿聲用的參考聲音。左邊清單、右邊詳情。
struct VoicesView: View {
    @Environment(StudioModel.self) private var model
    @Environment(\.undoManager) private var undo

    private var selected: Voice? { model.voices.first { $0.id == model.selectedVoice } }

    var body: some View {
        @Bindable var model = model
        HSplitView {
            List(selection: $model.selectedVoice) {
                ForEach(model.voices) { voice in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(voice.label)
                        Text("\(Formatting.duration(voice.seconds)) · \(voice.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .tag(voice.id)
                    .contextMenu {
                        Button("試聽") { model.player.play(voice.playable) }
                        Button("用這個聲音產生") { model.use(voice) }
                        Button("在 Finder 中顯示") { NSWorkspace.shared.activateFileViewerSelecting([voice.fileURL]) }
                        Divider()
                        Button("丟到垃圾桶", role: .destructive) { Task { await model.delete(voice, undo: undo) } }
                    }
                }
            }
            .listStyle(.inset)
            .frame(minWidth: 180, idealWidth: 220, maxWidth: 320)
            .onDeleteCommand {
                if let voice = selected { Task { await model.delete(voice, undo: undo) } }
            }
            .onKeyPress(.space) {
                if let voice = selected { model.player.toggle(voice.playable) }
                return .handled
            }
            // 把音檔拖進來就是新增聲音
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                model.beginAddVoice(file: url)
                return true
            }

            Group {
                if let voice = selected {
                    VoiceDetail(voice: voice)
                        .id(voice.id)
                } else {
                    ContentUnavailableView {
                        Label("還沒有聲音", systemImage: "person.wave.2")
                    } description: {
                        Text("錄一段 10 秒左右的聲音，或把音檔拖進來，就能用那個聲音唸任何稿子。")
                    } actions: {
                        Button("新增聲音…") { model.beginAddVoice() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("聲音庫")
        .navigationSubtitle("\(model.voices.count) 個聲音")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { model.beginAddVoice() } label: {
                    Label("新增聲音", systemImage: "plus")
                }
                .help("錄一段聲音或選音檔，做成新的仿聲聲音（⇧⌘N）")
            }
            SettingsToolbarItem()
        }
    }
}

struct VoiceDetail: View {
    @Environment(StudioModel.self) private var model
    @Environment(\.undoManager) private var undo
    let voice: Voice
    @State private var label = ""
    @State private var transcript = ""

    private var dirty: Bool {
        label.trimmingCharacters(in: .whitespaces) != voice.label
            || transcript.trimmingCharacters(in: .whitespacesAndNewlines) != voice.transcript
    }

    var body: some View {
        let playing = model.player.isPlaying(voice.playable.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TextField("名稱", text: $label)
                    .textFieldStyle(.plain)
                    .font(.songti(26))
                    .accessibilityLabel("聲音的名稱")

                HStack(spacing: 16) {
                    Label(Formatting.duration(voice.seconds), systemImage: "waveform")
                    Text(voice.name)
                    Text(Formatting.time(voice.created)).monospacedDigit()
                }
                .foregroundStyle(.secondary)
                .padding(.top, 8)

                HStack(spacing: 20) {
                    LinkAction(playing ? "暫停" : "試聽", systemImage: playing ? "pause.fill" : "play.fill") {
                        model.player.toggle(voice.playable)
                    }
                    LinkAction("用這個聲音產生", systemImage: "square.and.pencil") { model.use(voice) }
                    LinkAction("在 Finder 中顯示", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([voice.fileURL])
                    }
                    LinkAction("丟到垃圾桶", systemImage: "trash", role: .destructive) {
                        Task { await model.delete(voice, undo: undo) }
                    }
                }
                .padding(.top, 14)

                if let hint = voice.qualityHint {
                    Banner(text: hint)
                        .padding(.top, 18)
                }

                Divider().padding(.vertical, 22)

                SectionTitle("逐字稿")
                Text("要跟錄音內容一字不差，仿聲才會像。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                TextEditor(text: $transcript)
                    .font(.system(size: 15))
                    .lineSpacing(7)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.top, 10)
                    .accessibilityLabel("逐字稿")

                if dirty {
                    HStack {
                        Button("還原") {
                            label = voice.label
                            transcript = voice.transcript
                        }
                        Button("儲存變更") {
                            Task {
                                await model.updateVoice(voice, label: label.trimmingCharacters(in: .whitespaces),
                                                        transcript: transcript)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("s")
                        .disabled(transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.top, 14)
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            label = voice.label
            transcript = voice.transcript
        }
    }
}

// MARK: - 新增聲音

struct AddVoiceSheet: View {
    @Environment(StudioModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var recorder = Recorder()
    @State var pickedFile: URL?
    @State private var label = ""
    @State private var transcript = ""
    @State private var saving = false
    @State private var message: String?
    @State private var showImporter = false

    private var audioURL: URL? { pickedFile ?? recorder.fileURL }

    private var canSave: Bool {
        audioURL != nil && !saving && !recorder.isRecording
            && !label.trimmingCharacters(in: .whitespaces).isEmpty
            && !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("新增聲音").font(.title2.weight(.semibold))
            Text("錄 10 秒左右，環境安靜、不要有回音、照平常說話的速度。錄音內容要跟下面的逐字稿一字不差。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GroupBox("照著唸這段") {
                Text(model.script)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(4)
            }

            HStack(spacing: 10) {
                Button {
                    pickedFile = nil
                    Task { await recorder.toggle() }
                } label: {
                    Label(recorder.isRecording ? "停止錄音" : (recorder.fileURL == nil ? "開始錄音" : "重錄"),
                          systemImage: recorder.isRecording ? "stop.circle.fill" : "record.circle")
                }
                .tint(recorder.isRecording ? .red : nil)
                if recorder.isRecording {
                    ProgressView(value: Double(recorder.level))
                        .frame(width: 70)
                        .accessibilityLabel("音量")
                    Text(String(format: "%.0f 秒", recorder.elapsed))
                        .foregroundStyle(.red)
                        .monospacedDigit()
                } else if let url = audioURL {
                    Label(pickedFile != nil ? url.lastPathComponent : "錄好了", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .lineLimit(1)
                }
                Spacer()
                Button("選擇音檔…") { showImporter = true }
            }
            if let error = recorder.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            TextField("名稱", text: $label, prompt: Text("例：台灣男聲"))
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 4) {
                Text(pickedFile != nil ? "逐字稿（選了自己的音檔，要改成那段錄音的內容）" : "逐字稿")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $transcript)
                    .font(.body)
                    .frame(height: 64)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
                    .accessibilityLabel("逐字稿")
            }

            if let message {
                Text(message).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("取消", role: .cancel) {
                    recorder.stop()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(saving ? "儲存中…" : "儲存聲音") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 520)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { pick(url) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            pick(url)
            return true
        }
        .onAppear {
            if pickedFile == nil { transcript = model.script }
        }
    }

    private func pick(_ url: URL) {
        pickedFile = url
        // 自己的音檔內容不會是照唸稿，清掉避免存成錯的逐字稿
        if transcript == model.script { transcript = "" }
    }

    /// 代號由 app 產生（英數），使用者只需要取顯示名稱。
    private func makeName() -> String {
        let existing = Set(model.voices.map(\.name))
        var n = model.voices.count + 1
        while existing.contains("voice-\(n)") { n += 1 }
        return "voice-\(n)"
    }

    private func save() async {
        guard let url = audioURL else { return }
        saving = true
        defer { saving = false }
        do {
            let voice = try await model.client.addVoice(
                name: makeName(),
                label: label.trimmingCharacters(in: .whitespaces),
                transcript: transcript.trimmingCharacters(in: .whitespacesAndNewlines),
                fileURL: url)
            await model.refresh()
            model.selectedVoice = voice.id
            model.voiceName = voice.name
            dismiss()
        } catch {
            message = "儲存失敗：\(error.localizedDescription)"
        }
    }
}

/// 把一次產出存成聲音（聲音描述試到滿意的音色時用）。
struct SaveVoiceSheet: View {
    @Environment(StudioModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: HistoryItem
    @State private var label = ""
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("存成聲音").font(.title2.weight(.semibold))
            Text("把這段成品當成參考錄音存進聲音庫，之後用「仿聲」就能重現同一個音色。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.preview).lineLimit(3)
                    Text("\(item.modelName) · \(item.voiceLabel) · \(Formatting.duration(item.seconds))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
            if item.seconds < 3 {
                Label("這段不到 3 秒，仿聲可能不夠像；建議用 5 秒以上的成品。", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Color.signal)
            }
            TextField("名稱", text: $label, prompt: Text("例：溫暖女聲"))
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(saving ? "儲存中…" : "存成聲音") {
                    Task {
                        saving = true
                        defer { saving = false }
                        if await model.saveAsVoice(item, label: label.trimmingCharacters(in: .whitespaces)) {
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(saving || label.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
