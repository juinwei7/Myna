import Foundation

/// 比對前後兩次的佇列快照，找出「剛結束」的工作。
///
/// 佇列是用輪詢看的，工作也可能來自 Claude（經 MCP），所以不能只追蹤自己送出的那幾筆。
/// 第一次看到的已結束工作不算（否則一打開 app 就把舊結果當成新完成的）。
struct JobTracker {
    private var finished = Set<String>()
    private var primed = false

    mutating func update(_ jobs: [JobView]) -> [JobView] {
        let done = jobs.filter { !$0.isActive }
        defer {
            finished.formUnion(done.map(\.id))
            primed = true
        }
        guard primed else { return [] }
        return done.filter { !finished.contains($0.id) }
    }
}
