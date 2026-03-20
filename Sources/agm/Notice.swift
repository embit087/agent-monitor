import Foundation

struct Notice: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var at: Date
    var title: String
    var body: String
    var source: String?
    var action: String?
    var summary: String?
    var request: String?
    var rawResponseJSON: String?

    static func make(
        title rawTitle: String?,
        body rawBody: String?,
        source rawSource: String?,
        action rawAction: String?,
        summary rawSummary: String? = nil,
        request rawRequest: String? = nil,
        rawResponseJSON rawRawResponseJSON: String? = nil
    ) -> Notice {
        let title: String = {
            let t = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return t.isEmpty ? "Notification" : String(t.prefix(200))
        }()
        let bodyText: String = {
            let b = rawBody?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return b.isEmpty ? "No additional details." : String(b.prefix(8000))
        }()
        let source = rawSource.map {
            let s = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : String(s.prefix(120))
        } ?? nil
        let action = rawAction.map {
            let a = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return a.isEmpty ? nil : String(a.prefix(500))
        } ?? nil
        let summary = rawSummary.map {
            let s = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : String(s.prefix(8000))
        } ?? nil
        let request = rawRequest.map {
            let r = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return r.isEmpty ? nil : String(r.prefix(4000))
        } ?? nil
        let rawResponseJSON = rawRawResponseJSON.map {
            let r = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return r.isEmpty ? nil : r
        } ?? nil

        return Notice(
            id: UUID(),
            at: Date(),
            title: title,
            body: bodyText,
            source: source,
            action: action,
            summary: summary,
            request: request,
            rawResponseJSON: rawResponseJSON
        )
    }
}

private struct NotifyPayload: Decodable {
    var title: String?
    var body: String?
    var message: String?
    var text: String?
    var source: String?
    var action: String?
    var summary: String?
    var request: String?
    var raw_response_json: String?
    var rawResponseJSON: String?
    /// Claude Code hook / API shape; same role as `action` for Switch agent.
    var session_id: String?
    var sessionId: String?
}

private struct NoticeSocketMessage: Encodable {
    var type: String
    var id: String
    var at: String
    var title: String
    var body: String
    var source: String?
    var action: String?
    var summary: String?
    var request: String?
    var rawResponseJSON: String?

    init(notice: Notice) {
        type = "notice"
        id = notice.id.uuidString
        at = ISO8601DateFormatter().string(from: notice.at)
        title = notice.title
        body = notice.body
        source = notice.source
        action = notice.action
        summary = notice.summary
        request = notice.request
        rawResponseJSON = notice.rawResponseJSON
    }
}

private struct NotificationsEnvelope: Encodable {
    var notifications: [Notice]
}

enum NoticeCodec {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func decodeNotifyBody(from data: Data) throws -> Notice {
        let p = try JSONDecoder().decode(NotifyPayload.self, from: data)
        let text = p.body ?? p.message ?? p.text
        let action = firstNonEmpty(p.action, p.session_id, p.sessionId)
        let rawResponseJSON = firstNonEmpty(p.raw_response_json, p.rawResponseJSON)
        return Notice.make(
            title: p.title,
            body: text,
            source: p.source,
            action: action,
            summary: p.summary,
            request: p.request,
            rawResponseJSON: rawResponseJSON
        )
    }

    private static func firstNonEmpty(_ parts: String?...) -> String? {
        for part in parts {
            guard let part else { continue }
            let t = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return nil
    }

    static func encodeNoticeEvent(_ n: Notice) throws -> String {
        let data = try encoder.encode(NoticeSocketMessage(notice: n))
        return String(decoding: data, as: UTF8.self)
    }

    static func encodeList(_ items: [Notice]) throws -> Data {
        try encoder.encode(NotificationsEnvelope(notifications: items))
    }

    static func encodeReady(count: Int) -> String {
        "{\"type\":\"ready\",\"count\":\(count)}"
    }
}
