import Foundation

/// 內建配音員選單的一個選項（同一位配音員可能出現在多個模型裡，只列一次）。
struct SpeakerOption: Identifiable, Hashable {
    let id: String
    let label: String
    let note: String
}

/// 側欄「最近的稿子」的一列：同一份稿子只列一次，帶著它最新的那個版本與版本數。
struct RecentScript: Identifiable, Equatable {
    let latest: HistoryItem
    let count: Int

    var id: String { latest.id }
}

/// 「產生」頁的推導邏輯：哪些模型能用、預設選哪個、為什麼還不能產生。
///
/// 模型能做什麼以後端回傳的能力欄位為準（憲法 A1、A2），這裡只做畫面需要的篩選，
/// 抽成純函式是為了能測試，也避免同樣的判斷散在各個 View 裡。
enum ComposerLogic {
    /// 已下載、支援這個方式的模型；配音員方式再依模型裡有沒有這位過濾。
    static func usableModels(_ models: [ModelInfo], mode: Mode, speaker: String? = nil) -> [ModelInfo] {
        models.filter { m in
            guard m.isDownloaded, m.modes.contains(mode) else { return false }
            if mode == .preset, let speaker, !speaker.isEmpty { return m.hasPreset(speaker) }
            return true
        }
    }

    /// 選過且還能用就沿用；否則用這個方式的預設模型；預設的不能用就退到第一個。
    static func pickModel(_ usable: [ModelInfo], preferred: String?, mode: Mode) -> ModelInfo? {
        if let preferred, let hit = usable.first(where: { $0.id == preferred }) { return hit }
        return usable.first { $0.defaultFor.contains(mode) } ?? usable.first
    }

    /// 所有已下載模型的配音員，依出現順序去重複。
    static func speakers(_ models: [ModelInfo]) -> [SpeakerOption] {
        var seen = Set<String>()
        var result: [SpeakerOption] = []
        for m in models where m.isDownloaded && m.modes.contains(.preset) {
            for p in m.presets where seen.insert(p.id.lowercased()).inserted {
                result.append(SpeakerOption(id: p.id, label: p.label, note: p.note))
            }
        }
        return result
    }

    /// 語氣欄：模型宣告這個方式支援語氣才顯示。聲音描述有自己的欄位，不算在這裡。
    static func showsInstruct(_ model: ModelInfo?, mode: Mode) -> Bool {
        guard let model, mode != .design else { return false }
        return model.instructModes.contains(mode)
    }

    /// 比較清單：只留仍可用的模型，順序照模型清單；不足兩個就視同沒開比較。
    static func compareTargets(enabled: Bool, selected: Set<String>, usable: [ModelInfo]) -> [String] {
        guard enabled else { return [] }
        let ids = usable.map(\.id).filter(selected.contains)
        return ids.count >= 2 ? ids : []
    }

    /// 還不能產生的原因；可以產生時回傳 nil。
    static func blocker(text: String, mode: Mode, model: ModelInfo?, hasDownloadedModels: Bool,
                        voice: Voice?, speaker: String?, design: String, serviceRunning: Bool) -> String? {
        if !serviceRunning { return "語音服務還沒準備好" }
        if !hasDownloadedModels { return "還沒有模型，先到「模型」下載一個" }
        guard model != nil else { return "\(mode.label)還沒有可用的模型，先到「模型」下載" }
        switch mode {
        case .clone where voice == nil:
            return "先選一個聲音，或到「聲音庫」新增"
        case .preset where (speaker ?? "").isEmpty:
            return "先選一位配音員"
        case .design where design.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            return "先寫聲音描述"
        default:
            break
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "先寫稿子" }
        return nil
    }

    /// 把紀錄（新的在前）依稿子合併：同一份稿子試了幾次都只佔一列，順序照各自最新的那一次。
    static func recentScripts(_ history: [HistoryItem], limit: Int) -> [RecentScript] {
        var order: [String] = []
        var latest: [String: HistoryItem] = [:]
        var counts: [String: Int] = [:]
        for item in history {
            if latest[item.text] == nil {
                latest[item.text] = item
                order.append(item.text)
            }
            counts[item.text, default: 0] += 1
        }
        return order.prefix(limit).compactMap { text in
            latest[text].map { RecentScript(latest: $0, count: counts[text] ?? 1) }
        }
    }

    /// 語速能不能調：模型原生支援，或者這台 Mac 有 ffmpeg。
    static func speedAvailable(_ model: ModelInfo?, ffmpeg: Bool) -> Bool {
        (model?.nativeSpeed ?? false) || ffmpeg
    }
}
