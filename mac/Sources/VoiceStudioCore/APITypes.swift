import Foundation

/// 產生聲音的三種方式（對應後端的 mode）。
public enum Mode: String, Codable, CaseIterable, Identifiable, Sendable {
    case clone, preset, design

    public var id: String { rawValue }

    var label: String {
        switch self {
        case .clone: "仿聲"
        case .preset: "配音員"
        case .design: "聲音描述"
        }
    }

    var symbol: String {
        switch self {
        case .clone: "person.wave.2"
        case .preset: "music.mic"
        case .design: "text.bubble"
        }
    }
}

struct Preset: Codable, Identifiable, Hashable {
    let id: String
    let label: String
    let note: String
    let lang: String
}

/// 目錄裡的一個模型，加上它在這台 Mac 上的狀態。
struct ModelInfo: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let repo: String
    let family: String
    let sizeGb: Double
    let license: String
    let commercial: Bool
    let langs: [String]
    let modes: [Mode]
    let summary: String
    let notes: String
    let presets: [Preset]
    let instructModes: [Mode]
    let nativeSpeed: Bool
    let cloneText: String
    let sampleRate: Int
    let instructHint: String
    let designHint: String
    let recommended: Bool
    let custom: Bool

    let state: String          // available | downloading | downloaded
    let downloadedBytes: Int64
    let totalBytes: Int64?
    let progress: Double?
    let error: String?
    let loaded: Bool
    let loading: Bool
    let defaultFor: [Mode]

    var isDownloaded: Bool { state == "downloaded" }
    var isDownloading: Bool { state == "downloading" }

    func hasPreset(_ speaker: String) -> Bool {
        presets.contains { $0.id.caseInsensitiveCompare(speaker) == .orderedSame }
    }
}

/// 聲音庫裡的一個參考聲音。
struct Voice: Codable, Identifiable, Hashable {
    let id: String             // clone:<name>
    let name: String
    let label: String
    let note: String
    let transcript: String
    let seconds: Double
    let quality: String        // good | short | long
    let created: String
    let path: String

    var fileURL: URL { URL(fileURLWithPath: path) }

    var qualityHint: String? {
        switch quality {
        case "short": "錄音太短，建議 5 秒以上，仿聲才抓得到音色"
        case "long": "錄音偏長，10～20 秒就夠；太長會拖慢產生速度"
        default: nil
        }
    }
}

struct HistoryItem: Codable, Identifiable, Hashable {
    let id: String
    let created: String
    let text: String
    let spoken: String
    let mode: Mode
    let model: String
    let modelName: String
    let voice: String
    let voiceLabel: String
    let instruct: String
    let speed: Double
    let file: String
    let path: String
    let seconds: Double
    let batch: String?

    var fileURL: URL { URL(fileURLWithPath: path) }

    /// 清單裡顯示的一行稿子：把換行併成空格，多段的稿子才不會只看到第一行。
    var preview: String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}

struct JobView: Codable, Identifiable, Hashable {
    let jobId: String
    let kind: String           // synth | load
    let status: String         // queued | running | done | error | cancelled
    let progress: Double
    let stage: String
    let batch: String?
    let model: String?
    let modelName: String?
    let voiceLabel: String?
    let text: String?
    let error: String?
    /// 做完之後對應的紀錄代號
    let historyID: String?
    /// 做完之後成品的路徑
    let path: String?
    let queuedAt: Double?
    /// 做好要直接播出來（AI 工具的 speak）
    let speak: Bool?
    /// 稿子總共幾段（開始產生後才有）
    let segments: Int?
    /// 已經做好、可以先播的段數；只有一段的稿子不會有
    let parts: Int?
    let partsDir: String?

    var id: String { jobId }
    var isActive: Bool { status == "queued" || status == "running" }
    var wantsSpeak: Bool { speak == true }

    /// 已經做好的各段音檔，照順序。檔名是後端定的：`0001.wav`、`0002.wav`…
    var partURLs: [URL] {
        guard let partsDir, let parts, parts > 0 else { return [] }
        let dir = URL(fileURLWithPath: partsDir)
        return (1...parts).map { dir.appendingPathComponent(String(format: "%04d.wav", $0)) }
    }

    enum CodingKeys: String, CodingKey {
        case jobId, kind, status, progress, stage, batch, model, modelName, voiceLabel, text, error
        case path, queuedAt, speak, segments, parts, partsDir
        case historyID = "id"
    }
}

struct SettingsInfo: Codable, Equatable {
    var defaults: [String: String]
    /// 沒指定聲音時用的那一個（聲音的代號）；nil 是用聲音庫的第一個
    var defaultVoice: String?
    /// AI 工具能不能讓九官鳥直接播出聲音；舊版的服務沒有這一欄，當成可以
    var allowSpeak: Bool?
    var memoryBudgetGb: Double
    var memoryBudgetRange: [Double]

    func defaultModel(for mode: Mode) -> String? { defaults[mode.rawValue] }
}

struct Health: Codable {
    let ok: Bool
    let home: String
    let ffmpeg: Bool
    let modelsLoaded: [String]
    let modelCache: String
}

struct StudioError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// 可以交給播放列的東西（產出的音檔、聲音庫的參考錄音）。
struct Playable: Equatable {
    let id: String
    let url: URL
    let title: String
    let subtitle: String
}

extension HistoryItem {
    var playable: Playable {
        Playable(id: id, url: fileURL, title: preview, subtitle: "\(voiceLabel) · \(modelName)")
    }
}

extension JobView {
    /// 稿子的一行預覽（跟音檔清單同樣的做法）
    var preview: String {
        (text ?? "").split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    var playableSubtitle: String {
        [voiceLabel, modelName].compactMap { $0 }.joined(separator: " · ")
    }

    /// 做完的工作可以直接拿來播（不用先查到它的紀錄）。
    var playable: Playable? {
        guard status == "done", let historyID, let path else { return nil }
        return Playable(id: historyID, url: URL(fileURLWithPath: path), title: preview, subtitle: playableSubtitle)
    }
}

extension Voice {
    var playable: Playable {
        Playable(id: "voice:\(name)", url: fileURL, title: label, subtitle: "參考錄音")
    }
}
