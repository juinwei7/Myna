import Foundation

/// 語音服務的 HTTP API。
struct StudioClient {
    let base: URL

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    private struct OK: Codable { let ok: Bool }

    private func data(_ req: URLRequest) async throws -> Data {
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw StudioError(message: body?["detail"] as? String ?? "HTTP \(code)")
        }
        return data
    }

    private func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        try Self.decoder.decode(T.self, from: try await data(req))
    }

    private func request(_ method: String, _ path: String, body: Data? = nil) -> URLRequest {
        var req = URLRequest(url: base.appending(path: path))
        req.httpMethod = method
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        return req
    }

    private func call<T: Decodable>(_ method: String, _ path: String, _ payload: [String: Any]? = nil) async throws -> T {
        let body = try payload.map { try JSONSerialization.data(withJSONObject: $0) }
        return try await send(request(method, path, body: body))
    }

    // MARK: 狀態

    func health() async throws -> Health { try await call("GET", "api/health") }

    // MARK: 模型

    func models() async throws -> [ModelInfo] {
        struct Response: Codable { let models: [ModelInfo] }
        let r: Response = try await call("GET", "api/models")
        return r.models
    }

    func download(_ id: String) async throws -> ModelInfo { try await call("POST", "api/models/\(id)/download") }
    func cancelDownload(_ id: String) async throws -> ModelInfo { try await call("DELETE", "api/models/\(id)/download") }
    func load(_ id: String) async throws -> ModelInfo { try await call("POST", "api/models/\(id)/load") }
    func unload(_ id: String) async throws -> ModelInfo { try await call("POST", "api/models/\(id)/unload") }

    func deleteModel(_ id: String) async throws {
        let _: OK = try await call("DELETE", "api/models/\(id)")
    }

    func addCustomModel(repo: String) async throws -> ModelInfo {
        try await call("POST", "api/models/custom", ["repo": repo])
    }

    // MARK: 設定

    func settings() async throws -> SettingsInfo { try await call("GET", "api/settings") }

    func updateSettings(_ payload: [String: Any]) async throws -> SettingsInfo {
        try await call("PUT", "api/settings", payload)
    }

    // MARK: 聲音庫

    func voices() async throws -> (library: [Voice], script: String) {
        struct Response: Codable { let library: [Voice]; let script: String }
        let r: Response = try await call("GET", "api/voices")
        return (r.library, r.script)
    }

    func updateVoice(_ name: String, label: String? = nil, transcript: String? = nil) async throws -> Voice {
        var payload: [String: Any] = [:]
        if let label { payload["label"] = label }
        if let transcript { payload["transcript"] = transcript }
        return try await call("PATCH", "api/voices/\(name)", payload)
    }

    func deleteVoice(_ name: String) async throws {
        let _: OK = try await call("DELETE", "api/voices/\(name)")
    }

    func addVoice(name: String, label: String, transcript: String, fileURL: URL) async throws -> Voice {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        func append(_ s: String) { body.append(Data(s.utf8)) }
        for (key, value) in [("name", name), ("label", label), ("transcript", transcript)] {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n")
        }
        let ext = fileURL.pathExtension.isEmpty ? "wav" : fileURL.pathExtension
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"upload.\(ext)\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(try Data(contentsOf: fileURL))
        append("\r\n--\(boundary)--\r\n")

        var req = URLRequest(url: base.appending(path: "api/voices"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        return try await send(req)
    }

    // MARK: 工作

    /// 送出產生；`models` 有兩個以上就是比較，一次回傳多筆工作。
    func submit(_ payload: [String: Any]) async throws -> [JobView] {
        struct Batch: Codable { let jobs: [JobView]? }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let raw = try await data(request("POST", "api/jobs", body: body))
        if let jobs = try Self.decoder.decode(Batch.self, from: raw).jobs { return jobs }
        return [try Self.decoder.decode(JobView.self, from: raw)]
    }

    func jobs() async throws -> [JobView] {
        struct Response: Codable { let jobs: [JobView] }
        let r: Response = try await call("GET", "api/jobs")
        return r.jobs
    }

    func cancelJob(_ id: String) async throws -> JobView { try await call("DELETE", "api/jobs/\(id)") }

    // MARK: 紀錄

    func history(limit: Int = 500) async throws -> [HistoryItem] {
        struct Response: Codable { let items: [HistoryItem] }
        let url = base.appending(path: "api/history").appending(queryItems: [.init(name: "limit", value: "\(limit)")])
        let r: Response = try await send(URLRequest(url: url))
        return r.items
    }

    func deleteHistory(_ id: String) async throws {
        let _: OK = try await call("DELETE", "api/history/\(id)")
    }

    func restoreHistory(_ item: HistoryItem) async throws -> HistoryItem {
        try await send(request("POST", "api/history/restore", body: try Self.encoder.encode(item)))
    }

    func saveAsVoice(historyID: String, label: String) async throws -> Voice {
        try await call("POST", "api/history/\(historyID)/voice", ["label": label])
    }

    // MARK: 發音字典

    func pronounceRules() async throws -> [[String]] {
        struct Response: Codable { let rules: [[String]] }
        let r: Response = try await call("GET", "api/pronounce")
        return r.rules
    }

    func savePronounceRules(_ rules: [[String]]) async throws -> Int {
        struct Response: Codable { let rules: Int }
        let r: Response = try await call("PUT", "api/pronounce", ["rules": rules])
        return r.rules
    }
}
