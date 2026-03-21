import Foundation

actor CloudSync {
    private struct Cfg { let base: URL; let key: String }
    private let cfg: Cfg?
    private let instanceId: String
    private let log: AuditLog
    private let session: URLSession

    var isEnabled: Bool { cfg != nil }

    init() {
        let env = ProcessInfo.processInfo.environment
        instanceId = InstanceId.current
        log = AuditLog(instanceId: instanceId)

        let urlStr = env["AGM_CLOUD_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = env["AGM_CLOUD_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var urlTrimmed = urlStr
        if urlTrimmed.hasSuffix("/") { urlTrimmed = String(urlTrimmed.dropLast()) }

        cfg = (!urlTrimmed.isEmpty && URL(string: urlTrimmed) != nil)
            ? URL(string: urlTrimmed).map { Cfg(base: $0, key: key) }
            : nil

        let sc = URLSessionConfiguration.ephemeral
        sc.timeoutIntervalForRequest = 15
        sc.timeoutIntervalForResource = 30
        sc.waitsForConnectivity = false
        session = URLSession(configuration: sc)
    }

    // ── Public ───────────────────────────────────────────────────────────────

    func syncNotice(_ notice: Notice) {
        guard let cfg else { return }
        Task.detached(priority: .utility) { [weak self] in
            await self?._uploadNoticeRetrying(notice, cfg: cfg)
        }
    }

    func auditAppStarted() {
        _enqueue(AuditEvent.make(event: AuditEvent.EventKind.appStarted))
    }

    func auditServerStarted(port: UInt16) {
        var e = AuditEvent.make(event: AuditEvent.EventKind.serverStarted)
        e.action = "port:\(port)"
        _enqueue(e)
    }

    func auditNoticeReceived(_ notice: Notice) {
        var e = AuditEvent.make(event: AuditEvent.EventKind.noticeReceived)
        e.noticeId = notice.id.uuidString.replacingOccurrences(of: "-", with: "")
        e.source = notice.source
        e.action = notice.action
        e.title = notice.title
        _enqueue(e)
    }

    func auditNoticeCleared(count: Int) {
        var e = AuditEvent.make(event: AuditEvent.EventKind.noticeCleared)
        e.durationMs = count
        _enqueue(e)
    }

    func auditSwitchAttempted(sessionId: String) {
        var e = AuditEvent.make(event: AuditEvent.EventKind.terminalSwitchAttempted)
        e.sessionId = sessionId
        _enqueue(e)
    }

    func auditSwitchResult(sessionId: String, ok: Bool, error: String?, durationMs: Int) {
        let kind = ok ? AuditEvent.EventKind.terminalSwitchSucceeded
                      : AuditEvent.EventKind.terminalSwitchFailed
        var e = AuditEvent.make(event: kind)
        e.sessionId = sessionId
        e.result = ok ? "ok" : "failed"
        e.error = error
        e.durationMs = durationMs
        _enqueue(e)
    }

    func loadHistory(limit: Int = 500) async -> [Notice] {
        guard let cfg else { return [] }
        var comps = URLComponents(
            url: cfg.base.appendingPathComponent("api/notices"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "instance_id", value: instanceId),
            URLQueryItem(name: "limit", value: String(min(limit, 2000))),
        ]
        guard let url = comps.url else { return [] }

        var req = URLRequest(url: url)
        _auth(&req, cfg: cfg)

        guard let (data, resp) = try? await session.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else {
            return []
        }

        struct Env: Decodable { var notifications: [CN] }
        struct CN: Decodable {
            var id, at, title, body: String
            var source, action, summary, request, raw_response_json: String?
        }

        guard let env = try? JSONDecoder().decode(Env.self, from: data) else { return [] }

        let fmtMs = ISO8601DateFormatter()
        fmtMs.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fmtSec = ISO8601DateFormatter()
        fmtSec.formatOptions = [.withInternetDateTime]

        return env.notifications.compactMap { cn -> Notice? in
            let raw = cn.id
            let uuidStr: String
            if raw.count == 32 {
                let s = raw
                uuidStr = "\(s.prefix(8))-\(s.dropFirst(8).prefix(4))-\(s.dropFirst(12).prefix(4))-\(s.dropFirst(16).prefix(4))-\(s.dropFirst(20))"
            } else {
                uuidStr = raw
            }
            guard let uuid = UUID(uuidString: uuidStr) else { return nil }
            let date = fmtMs.date(from: cn.at) ?? fmtSec.date(from: cn.at) ?? Date()
            return Notice(
                id: uuid,
                at: date,
                title: cn.title,
                body: cn.body,
                source: cn.source,
                action: cn.action,
                summary: cn.summary,
                request: cn.request,
                rawResponseJSON: cn.raw_response_json
            )
        }
    }

    // ── Private ──────────────────────────────────────────────────────────────

    private func _enqueue(_ evt: AuditEvent) {
        guard cfg != nil else { return }
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.log.enqueue(evt)
            await self._flushAudit()
        }
    }

    private func _flushAudit() async {
        guard let cfg else { return }
        let batch = await log.peek(max: 50)
        guard !batch.isEmpty else { return }
        if (try? await _postAudit(batch, cfg: cfg)) != nil {
            await log.drain(count: batch.count)
        }
    }

    private func _postAudit(_ events: [AuditEvent], cfg: Cfg) async throws {
        var req = URLRequest(url: cfg.base.appendingPathComponent("api/audit"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _auth(&req, cfg: cfg)
        req.httpBody = try JSONEncoder().encode(events)

        let (_, r) = try await session.data(for: req)
        guard let h = r as? HTTPURLResponse, (200...299).contains(h.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func _uploadNoticeRetrying(_ notice: Notice, cfg: Cfg) async {
        for attempt in 0...2 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: UInt64(500_000_000) * UInt64(1 << (attempt - 1)))
            }
            do {
                try await _uploadNotice(notice, cfg: cfg)
                return
            } catch {
                if attempt == 2 {
                    fputs("agm: cloud sync failed: \(error)\n", stderr)
                }
            }
        }
    }

    private func _uploadNotice(_ notice: Notice, cfg: Cfg) async throws {
        struct Payload: Encodable {
            var id, instance_id, at, title, body: String
            var source, action, summary, request, raw_response_json: String?
        }

        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let p = Payload(
            id: notice.id.uuidString.replacingOccurrences(of: "-", with: ""),
            instance_id: instanceId,
            at: fmt.string(from: notice.at),
            title: notice.title,
            body: notice.body,
            source: notice.source,
            action: notice.action,
            summary: notice.summary,
            request: notice.request,
            raw_response_json: notice.rawResponseJSON
        )

        var req = URLRequest(url: cfg.base.appendingPathComponent("api/notices"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _auth(&req, cfg: cfg)
        req.httpBody = try JSONEncoder().encode(p)

        let (_, r) = try await session.data(for: req)
        guard let h = r as? HTTPURLResponse, (200...299).contains(h.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func _auth(_ req: inout URLRequest, cfg: Cfg) {
        if !cfg.key.isEmpty {
            req.setValue("Bearer \(cfg.key)", forHTTPHeaderField: "Authorization")
        }
    }
}
