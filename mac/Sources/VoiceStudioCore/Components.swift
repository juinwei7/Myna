import AppKit
import SwiftUI

/// 小標籤：能力、授權、預設等短資訊。
struct Chip: View {
    let text: String
    var tint: Color?

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(tint ?? .secondary)
            .background((tint ?? .secondary).opacity(0.14), in: Capsule())
    }
}

// MARK: - 稿子的一個版本

/// 同一份稿子的各個版本，差別在模型與聲音，所以模型名稱放最前面。
struct TakeRow: View {
    @Environment(StudioModel.self) private var model
    let item: HistoryItem

    var body: some View {
        let playing = model.player.isPlaying(item.id)
        HStack(spacing: 10) {
            Button { model.selection = [item.id]; model.player.toggle(item.playable) } label: {
                HStack(spacing: 10) {
                    Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(playing ? AnyShapeStyle(Color.persimmon) : AnyShapeStyle(.secondary))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(item.modelName)
                                .fontWeight(.medium)
                            if item.batch != nil { Chip(text: "比較", tint: .persimmon) }
                        }
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(Formatting.duration(item.seconds))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(playing ? "暫停" : "播放")：\(item.modelName)，\(item.voiceLabel)")

            Button { model.showDetail(item) } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("顯示詳情")
            .accessibilityLabel("顯示詳情")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .rowBackground(selected: model.selection.contains(item.id))
    }

    private var detail: String {
        var parts = [item.voiceLabel]
        if !item.instruct.isEmpty, item.mode != .design { parts.append(item.instruct) }
        if abs(item.speed - 1) > 0.01 { parts.append(String(format: "%.2f×", item.speed)) }
        parts.append(Formatting.time(item.created))
        return parts.joined(separator: "　")
    }
}

/// 進行中的工作：進度、階段、取消。
struct JobRow: View {
    @Environment(StudioModel.self) private var model
    let job: JobView

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(job.modelName ?? "")
                        .fontWeight(.medium)
                    Text(job.stage)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                ProgressView(value: job.status == "queued" ? 0 : job.progress)
                    .progressViewStyle(.linear)
                    .accessibilityLabel("\(job.modelName ?? "")的進度")
            }
            Button { model.cancel(job) } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("取消")
            .accessibilityLabel("取消這個工作")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }
}

/// 音檔的右鍵選單（各處共用）。
struct HistoryMenu: View {
    let model: StudioModel
    let items: [HistoryItem]
    let undo: UndoManager?

    var body: some View {
        if items.count == 1, let one = items.first {
            Button("播放") { model.play(one) }
            Button("顯示詳情") { model.showDetail(one) }
            Divider()
            Button("用這份稿子") { model.reuse(one) }
            Button("存成聲音…") { model.saveVoiceItem = one }
            Divider()
        }
        if !items.isEmpty {
            Button("在 Finder 中顯示") { model.reveal(items) }
            Button("拷貝檔案路徑") { model.copyPath(items) }
            if items.count == 1, let one = items.first {
                ShareLink(item: one.fileURL)
            }
            Divider()
            Button(items.count > 1 ? "把 \(items.count) 個音檔丟到垃圾桶" : "丟到垃圾桶", role: .destructive) {
                Task { await model.delete(items, undo: undo) }
            }
        }
    }
}

// MARK: - 播放列

struct WaveformView: View {
    let peaks: [Float]
    let progress: Double
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let count = max(1, min(peaks.count, Int(size.width / 3)))
                let slot = size.width / CGFloat(count)
                let barWidth = max(1.5, slot * 0.62)
                for i in 0..<count {
                    // 視窗變窄時格數變少，從原本的峰值裡取樣
                    let source = peaks.isEmpty ? 0 : peaks[min(peaks.count - 1, i * peaks.count / count)]
                    let h = max(2, CGFloat(source) * size.height)
                    let rect = CGRect(x: CGFloat(i) * slot + (slot - barWidth) / 2, y: (size.height - h) / 2,
                                      width: barWidth, height: h)
                    let played = Double(i) / Double(count) < progress
                    context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2),
                                 with: played ? .color(.persimmon) : .color(.secondary.opacity(0.4)))
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                onSeek(min(max(value.location.x / max(geo.size.width, 1), 0), 1))
            })
        }
        .accessibilityRepresentation {
            Slider(value: Binding(get: { progress }, set: onSeek), in: 0...1) { Text("播放位置") }
        }
    }
}

/// 底部播放列：播放、目前時間、波形、總長、倍速。
/// 邊產生邊播時的進度條：深色是播過的、淺色是做好還沒播的、底色是還沒做的。
struct LiveProgressView: View {
    /// 播到哪了（0～1）
    let played: Double
    /// 做到哪了（0～1）
    let ready: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(Color.primary.opacity(0.22))
                    .frame(width: geo.size.width * min(max(ready, 0), 1))
                Capsule().fill(Color.persimmon)
                    .frame(width: geo.size.width * min(max(played, 0), 1))
            }
            .frame(height: 6)
            .frame(maxHeight: .infinity, alignment: .center)
            .animation(.linear(duration: 0.1), value: played)
            .animation(.easeOut(duration: 0.3), value: ready)
        }
    }
}

struct PlayerBar: View {
    @Environment(StudioModel.self) private var model

    private func speedLabel(_ rate: Float) -> String {
        rate == rate.rounded() ? "\(Int(rate))×" : String(format: "%g×", rate)
    }

    var body: some View {
        let player = model.player
        if let item = player.current {
            HStack(spacing: 12) {
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(player.isPlaying ? "暫停" : "播放")
                .accessibilityLabel(player.isPlaying ? "暫停" : "播放")

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.callout.weight(.medium)).lineLimit(1)
                    Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(width: 170, alignment: .leading)
                .contentShape(Rectangle())
                // 只有標題這塊能把檔案拖出去；波形上的拖曳留給跳轉。還在產生的沒有完整的檔可以拖
                .onDrag { player.live == nil ? NSItemProvider(contentsOf: item.url) ?? NSItemProvider() : NSItemProvider() }
                .help(player.live == nil ? "可以把音檔拖到別的地方" : "還在產生，做完才有完整的音檔")

                Text(Formatting.clock(player.position))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)

                if let live = player.live {
                    // 邊產生邊播：後面的還不存在，沒有波形可以畫，改畫做到哪、播到哪
                    LiveProgressView(played: player.liveProgress,
                                     ready: Double(live.parts.count) / Double(max(live.total, 1)))
                        .frame(height: 30)
                        .accessibilityLabel("已經做好 \(live.parts.count) 段，共 \(live.total) 段")

                    // 寫的是播到第幾段；做到第幾段看進度條淺色的部分，佇列那一列也有
                    Text(live.waiting ? "等下一段…" : "第 \(live.index + 1)／\(live.total) 段")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 84, alignment: .leading)
                        .help("還在產生：已經做好 \(live.parts.count) 段，共 \(live.total) 段。整份做完就會出現波形，可以拖曳跳轉")
                } else {
                    WaveformView(peaks: player.peaks,
                                 progress: player.duration > 0 ? player.position / player.duration : 0) {
                        player.seek($0 * player.duration)
                    }
                    .frame(height: 30)

                    Text(Formatting.clock(player.duration))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .leading)
                }

                Menu {
                    ForEach(Player.rates, id: \.self) { value in
                        Button { player.rate = value } label: {
                            if value == player.rate {
                                Label(speedLabel(value), systemImage: "checkmark")
                            } else {
                                Text(speedLabel(value))
                            }
                        }
                    }
                } label: {
                    Text(speedLabel(player.rate)).monospacedDigit()
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .foregroundStyle(Color.persimmon)
                .help("試聽的播放速度（不影響音檔本身）")
                .accessibilityLabel("播放速度")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }
}
