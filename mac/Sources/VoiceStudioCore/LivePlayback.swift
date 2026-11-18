import Foundation

/// 邊產生邊播：一段播完之後要做什麼。
enum LiveStep: Equatable {
    /// 播第幾段（從 0 算）
    case playPart(Int)
    /// 下一段還沒做好，等
    case wait
    /// 整份做完了：換成完整的音檔，從這個位置接著播
    case switchToFinal(offset: Double)
}

enum LiveLogic {
    /// - Parameters:
    ///   - index: 剛播完的是第幾段
    ///   - ready: 已經做好幾段
    ///   - finished: 整份是不是做完了（完整的音檔已經存好）
    ///   - played: 到剛播完這一段為止，總共播了幾秒
    ///
    /// 完整的音檔就是各段接起來，所以「已經播了幾秒」就是它裡面該接下去的位置。
    /// 做完就換過去，不繼續一段一段播：換過去之後才有波形、才能跳轉。
    static func afterPart(_ index: Int, ready: Int, finished: Bool, played: Double) -> LiveStep {
        if finished { return .switchToFinal(offset: played) }
        if index + 1 < ready { return .playPart(index + 1) }
        return .wait
    }
}

/// AI 工具要九官鳥唸出來的那些工作，照送來的順序一筆一筆播。
///
/// 佇列是輪詢看到的，所以跟 `JobTracker` 一樣：app 剛打開時已經做完的不算。
struct SpeakQueue {
    enum Action: Equatable {
        case none
        /// 還在產生，但已經有段落可以先播
        case live(JobView)
        /// 已經做完，播成品
        case play(JobView)
    }

    private var seen = Set<String>()
    private var primed = false
    private(set) var pending: [String] = []

    mutating func note(_ jobs: [JobView]) {
        let speaking = jobs.filter { $0.kind == "synth" && $0.wantsSpeak }
        let fresh = speaking
            .filter { !seen.contains($0.id) && (primed || $0.isActive) }
            .sorted { ($0.queuedAt ?? 0) < ($1.queuedAt ?? 0) }
        pending.append(contentsOf: fresh.map(\.id))
        seen.formUnion(speaking.map(\.id))
        primed = true
    }

    /// 排著還沒播的全部不播了。
    mutating func flush() { pending.removeAll() }

    /// 播放器閒著時問一次：現在該播哪一筆。
    /// 最前面那筆還沒有東西可以播就等它，不跳過去播後面的，順序才不會亂。
    mutating func next(_ jobs: [JobView], playerIdle: Bool) -> Action {
        guard playerIdle else { return .none }
        while let id = pending.first {
            guard let job = jobs.first(where: { $0.id == id }) else {
                pending.removeFirst()
                continue
            }
            switch job.status {
            case "done":
                pending.removeFirst()
                return .play(job)
            case "error", "cancelled":
                pending.removeFirst()
            default:
                guard (job.parts ?? 0) >= 1 else { return .none }
                pending.removeFirst()
                return .live(job)
            }
        }
        return .none
    }
}
