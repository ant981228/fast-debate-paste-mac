import Foundation

/// Native integration client for CardMirror's loopback HTTP bridge.
///
/// Wire contract: docs/cardmirror-integration-spec.md. CardMirror writes a
/// discovery file with a per-launch port + token; we read it, `GET /ping`
/// to confirm the server is live, then `POST /insert`. Any failure returns
/// `.fallback(...)` so the caller drops to the keystroke path — a paste is
/// never lost.
///
/// Calls are synchronous (a `URLSession` task driven by a semaphore); the
/// caller already runs on a background queue, so blocking is fine.
enum CardMirrorClient {
    enum Outcome {
        case inserted
        case fallback(String)  // reason, for logging
    }

    /// The role/intent of an insertion, matching the spec's `role` field.
    enum Role: String {
        case card, cite, inline
    }

    private struct Discovery: Decodable {
        let schema: Int
        let port: Int
        let token: String
    }

    /// Attempt a native insert. Returns `.inserted` on success, or
    /// `.fallback(reason)` when the bridge is unavailable / refused, so the
    /// caller can use keystrokes instead.
    static func insert(text: String,
                       role: Role,
                       newParagraph: Bool,
                       omitted: Bool,
                       config: Config) -> Outcome {
        guard let discovery = readDiscovery(at: config.discoveryFilePath) else {
            return .fallback("no discovery file (CardMirror not running?)")
        }
        guard discovery.schema == 1 else {
            return .fallback("unsupported schema \(discovery.schema)")
        }

        // 1. /ping — confirm the server is alive and answering.
        switch get("http://127.0.0.1:\(discovery.port)/ping",
                   token: discovery.token,
                   timeoutMs: config.httpPingTimeoutMs) {
        case .failure(let reason):
            return .fallback("ping: \(reason)")
        case .success(let (status, data)):
            guard status == 200, jsonOK(data) else {
                return .fallback("ping not ok (status \(status))")
            }
        }

        // 2. /insert
        let body: [String: Any] = [
            "text": text,
            "role": role.rawValue,
            "newParagraph": newParagraph,
            "omitted": omitted,
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return .fallback("encode body")
        }
        switch post("http://127.0.0.1:\(discovery.port)/insert",
                    token: discovery.token,
                    body: bodyData,
                    timeoutMs: config.httpInsertTimeoutMs) {
        case .failure(let reason):
            return .fallback("insert: \(reason)")
        case .success(let (status, data)):
            if status == 200, jsonOK(data) {
                return .inserted
            }
            // ok:false (no-target-doc, doc-readonly, …) or non-2xx → fall
            // back so the paste still lands via keystrokes.
            return .fallback("insert refused (status \(status)\(jsonError(data).map { ", \($0)" } ?? ""))")
        }
    }

    // MARK: - Discovery

    private static func readDiscovery(at path: String) -> Discovery? {
        let expanded = (path as NSString).expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: expanded) else { return nil }
        return try? JSONDecoder().decode(Discovery.self, from: data)
    }

    // MARK: - HTTP (synchronous)

    private enum HTTPResult {
        case success((status: Int, data: Data))
        case failure(String)
    }

    private static func get(_ urlString: String, token: String, timeoutMs: Int) -> HTTPResult {
        guard let url = URL(string: urlString) else { return .failure("bad url") }
        var req = URLRequest(url: url, timeoutInterval: Double(timeoutMs) / 1000.0)
        req.httpMethod = "GET"
        req.setValue(token, forHTTPHeaderField: "X-FDP-Token")
        return send(req)
    }

    private static func post(_ urlString: String, token: String, body: Data, timeoutMs: Int) -> HTTPResult {
        guard let url = URL(string: urlString) else { return .failure("bad url") }
        var req = URLRequest(url: url, timeoutInterval: Double(timeoutMs) / 1000.0)
        req.httpMethod = "POST"
        req.setValue(token, forHTTPHeaderField: "X-FDP-Token")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        return send(req)
    }

    private static func send(_ request: URLRequest) -> HTTPResult {
        let semaphore = DispatchSemaphore(value: 0)
        var result: HTTPResult = .failure("no response")
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error = error {
                result = .failure(error.localizedDescription)
                return
            }
            guard let http = response as? HTTPURLResponse else {
                result = .failure("non-HTTP response")
                return
            }
            result = .success((status: http.statusCode, data: data ?? Data()))
        }
        task.resume()
        semaphore.wait()
        return result
    }

    // MARK: - JSON helpers

    /// True when the response body parses to an object with `ok == true`.
    private static func jsonOK(_ data: Data) -> Bool {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return (obj["ok"] as? Bool) == true
    }

    /// The `error` string from a failure body, if present.
    private static func jsonError(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj["error"] as? String
    }
}
