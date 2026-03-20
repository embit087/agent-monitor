import Foundation
import SwiftUI

@MainActor
final class PanelModel: ObservableObject {
    @Published private(set) var items: [Notice] = []
    @Published private(set) var serverRunning = false
    @Published private(set) var lastError: String?

    let port: UInt16
    let maxItems: Int
    let secret: String?
    /// Resolved `winid` script path: `NOTIFY_MAILBOX_WINID` / `WINID_SCRIPT`, then `~/embitious/tools/winid`, repo sibling `tools/winid`, etc.
    let winidExecutableURL: URL?
    let hub = BrowserHub()

    private var serverTask: Task<Void, Never>?

    init() {
        let env = ProcessInfo.processInfo.environment
        if let p = env["NOTIFY_MAILBOX_PORT"].flatMap(UInt16.init), p > 0 {
            port = p
        } else if let p = env["PORT"].flatMap(UInt16.init), p > 0 {
            port = p
        } else {
            port = 3847
        }
        let rawMax = env["NOTIFY_MAILBOX_MAX"].flatMap(Int.init) ?? 500
        maxItems = min(max(1, rawMax), 5000)
        let s = env["NOTIFY_MAILBOX_SECRET"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        secret = (s?.isEmpty == false) ? s : nil
        winidExecutableURL = WinidLocator.resolve(environment: env)
    }

    func startServerIfNeeded() {
        guard serverTask == nil else { return }
        serverTask = Task { [weak self] in
            await self?.runServerLoop()
        }
    }

    private func runServerLoop() async {
        do {
            try await LocalHTTPServer.run(
                port: port,
                secret: secret,
                hub: hub,
                viewModel: self
            )
        } catch {
            await MainActor.run {
                lastError = Self.userFacingServerError(error)
                serverRunning = false
            }
        }
    }

    func applyAppend(_ notice: Notice, postSystemNotification: Bool = true) {
        items.insert(notice, at: 0)
        while items.count > maxItems {
            items.removeLast()
        }
        if postSystemNotification {
            SystemNotificationSupport.postNotice(notice)
        }
    }

    func applyClear() {
        items.removeAll()
    }

    func snapshotItems() -> [Notice] {
        items
    }

    func markServerListening() {
        serverRunning = true
        lastError = nil
    }

    func clearListFromUI() async {
        applyClear()
        await hub.broadcast(#"{"type":"clear"}"#)
    }

    func upsertManualTerminalTrigger(_ winidRaw: String) async {
        let winid = winidRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !winid.isEmpty else { return }

        items.removeAll { notice in
            let title = notice.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let source = notice.source?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let action = notice.action?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return title.localizedStandardContains("terminal")
                && source.compare("Manual", options: .caseInsensitive) == .orderedSame
                && action == winid
        }

        let notice = Notice.make(
            title: "Terminal",
            body: "Manual switch target for WINID \(winid).",
            source: "Manual",
            action: winid
        )
        applyAppend(notice, postSystemNotification: false)
        if let json = try? NoticeCodec.encodeNoticeEvent(notice) {
            await hub.broadcast(json)
        }
    }

    /// Runs `winid open <id>` as a **Terminal.app** shell command (not from this process).
    /// Most ids come from agent sessions, but manual Terminal triggers can use any saved WINID.
    func openWinidSession(_ sessionIdRaw: String) {
        WinidTerminalRunner.openSession(
            sessionId: sessionIdRaw,
            winidPath: winidExecutableURL?.path
        )
    }

    /// Surfaces system failures in plain language instead of NSError wording.
    private static func userFacingServerError(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain, ns.code == 48 { // EADDRINUSE
            return "This notification server is already running. Close the other Agent Monitor window or wait a moment, then try again."
        }
        let msg = error.localizedDescription.lowercased()
        if msg.contains("address already in use") || msg.contains("already in use") {
            return "This notification server is already running. Close the other Agent Monitor window or wait a moment, then try again."
        }
        return "Couldn’t finish starting up. Quit and reopen the app, or try again in a few seconds."
    }
}
