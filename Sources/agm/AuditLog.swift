import Foundation

// MARK: - AuditEvent

struct AuditEvent: Encodable, Sendable {
    let v: Int = 1
    let id: String
    let event: String
    let at: String
    var instanceId: String?
    var sessionId: String?
    var noticeId: String?
    var source: String?
    var action: String?
    var title: String?
    var result: String?
    var error: String?
    var durationMs: Int?

    enum EventKind {
        static let appStarted              = "app.started"
        static let serverStarted           = "server.started"
        static let noticeReceived          = "notice.received"
        static let noticeCleared           = "notice.cleared"
        static let terminalSwitchAttempted = "terminal.switch.attempted"
        static let terminalSwitchSucceeded = "terminal.switch.succeeded"
        static let terminalSwitchFailed    = "terminal.switch.failed"
    }

    static func make(event: String) -> AuditEvent {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return AuditEvent(
            id: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
            event: event,
            at: fmt.string(from: Date())
        )
    }
}

// MARK: - AuditLog actor

actor AuditLog {
    static let maxPending = 1000

    private(set) var pending: [AuditEvent] = []
    private let instanceId: String

    init(instanceId: String) {
        self.instanceId = instanceId
    }

    func enqueue(_ base: AuditEvent) {
        var evt = base
        evt.instanceId = instanceId
        if pending.count >= Self.maxPending {
            pending.removeFirst()
        }
        pending.append(evt)
    }

    func peek(max: Int) -> [AuditEvent] {
        Array(pending.prefix(max))
    }

    func drain(count: Int) {
        pending.removeFirst(min(count, pending.count))
    }
}
