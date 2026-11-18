import Foundation

/// 顯示用的文字格式。
enum Formatting {
    static func bytes(_ value: Int64) -> String {
        let gb = Double(value) / 1_000_000_000
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        return String(format: "%.0f MB", Double(value) / 1_000_000)
    }

    static func size(gb: Double) -> String {
        gb >= 1 ? String(format: "%.1f GB", gb) : String(format: "%.0f MB", gb * 1000)
    }

    /// 清單裡的長度：一分鐘內用秒，超過用分秒。
    static func duration(_ seconds: Double) -> String {
        if seconds < 60 { return String(format: "%.1f 秒", seconds) }
        let s = Int(seconds.rounded())
        return "\(s / 60) 分 \(String(format: "%02d", s % 60)) 秒"
    }

    /// 播放列的時間。
    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return "準備中…" }
        return "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%"
    }

    static func parse(_ iso: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: iso)
    }

    /// 今天只顯示時間，其他日子加上日期。
    static func time(_ iso: String, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date = parse(iso) else { return iso }
        let f = DateFormatter()
        f.dateFormat = calendar.isDate(date, inSameDayAs: now) ? "HH:mm" : "M/d HH:mm"
        return f.string(from: date)
    }

    static func langs(_ codes: [String]) -> String {
        let names = ["zh": "中文", "en": "英文", "ja": "日文", "ko": "韓文"]
        return codes.map { names[$0] ?? $0 }.joined(separator: "、")
    }
}
