import AVFoundation

/// 播放列的波形：把整段音訊縮成固定格數的峰值。
enum Waveform {
    /// 每一格取絕對值的最大值，再把整體正規化到 0～1。
    static func peaks(_ samples: [Float], bins: Int) -> [Float] {
        guard bins > 0 else { return [] }
        guard !samples.isEmpty else { return Array(repeating: 0, count: bins) }
        var result = [Float](repeating: 0, count: bins)
        let per = Double(samples.count) / Double(bins)
        for bin in 0..<bins {
            let start = Int(Double(bin) * per)
            let end = max(start + 1, min(samples.count, Int(Double(bin + 1) * per)))
            var peak: Float = 0
            for i in start..<min(end, samples.count) { peak = max(peak, abs(samples[i])) }
            result[bin] = peak
        }
        let top = result.max() ?? 0
        return top > 0 ? result.map { $0 / top } : result
    }

    /// 讀音檔算峰值；讀不了就回空陣列，播放列會退回一般的進度條。
    static func load(_ url: URL, bins: Int = 160) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url),
              file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(min(file.length, 48_000 * 1800))),
              (try? file.read(into: buffer)) != nil,
              let channel = buffer.floatChannelData?[0]
        else { return [] }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        return peaks(samples, bins: bins)
    }
}
