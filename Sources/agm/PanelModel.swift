import AppKit
import Foundation
import SwiftUI

@MainActor
final class PanelModel: ObservableObject {
    enum SwitchStatus: Equatable {
        case idle
        case switching(String)
        case succeeded(String)
        case failed(String)
    }

    enum PreviewStatus: Equatable {
        case idle
        case loading
        case loaded(String)
        case notFound(String)
        case permissionNeeded
    }

    @Published private(set) var items: [Notice] = []
    @Published private(set) var serverRunning = false
    @Published private(set) var lastError: String?
    @Published private(set) var switchStatus: SwitchStatus = .idle
    @Published private(set) var previewImage: NSImage?
    @Published private(set) var previewStatus: PreviewStatus = .idle

    let port: UInt16
    let maxItems: Int
    let secret: String?
    /// Resolved `winid` script path: `NOTIFY_MAILBOX_WINID` / `WINID_SCRIPT`, then `~/embitious/tools/winid`, repo sibling `tools/winid`, etc.
    let winidExecutableURL: URL?
    let hub = BrowserHub()
    let cloudSync = CloudSync()

    private var serverTask: Task<Void, Never>?
    private var switchStatusClearTask: Task<Void, Never>?
    private var switchTimes: [String: Date] = [:]

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

    func startServerIfNeeded(notepad: NotepadModel) {
        guard serverTask == nil else { return }
        serverTask = Task { [weak self] in
            await self?.runServerLoop(notepad: notepad)
        }
    }

    private func runServerLoop(notepad: NotepadModel) async {
        do {
            try await LocalHTTPServer.run(
                port: port,
                secret: secret,
                hub: hub,
                viewModel: self,
                notepad: notepad
            )
        } catch {
            await MainActor.run {
                lastError = Self.userFacingServerError(error)
                serverRunning = false
            }
        }
    }

    func applyAppend(_ notice: Notice, postSystemNotification: Bool = true) {
        // Suppress rapid replays with identical payload (e.g. Cursor firing both user-level and
        // workspace `stop` hooks, or duplicate entries in hooks.json). Each POST still mints a new UUID.
        if let newest = items.first, Self.isRapidDuplicate(of: newest, incoming: notice) {
            return
        }
        items.insert(notice, at: 0)
        while items.count > maxItems {
            items.removeLast()
        }
        if postSystemNotification {
            SystemNotificationSupport.postNotice(notice)
        }
        Task.detached(priority: .utility) { [weak self] in
            await self?.cloudSync.syncNotice(notice)
            await self?.cloudSync.auditNoticeReceived(notice)
        }
    }

    /// Same logical notification posted twice within this window (different `Notice.id`) counts as one.
    private static func isRapidDuplicate(of recent: Notice, incoming: Notice) -> Bool {
        let window: TimeInterval = 2.5
        guard abs(incoming.at.timeIntervalSince(recent.at)) < window else { return false }
        guard recent.title == incoming.title, recent.body == incoming.body else { return false }
        guard (recent.source ?? "") == (incoming.source ?? "") else { return false }
        guard (recent.action ?? "") == (incoming.action ?? "") else { return false }
        guard (recent.summary ?? "") == (incoming.summary ?? "") else { return false }
        guard (recent.request ?? "") == (incoming.request ?? "") else { return false }
        guard (recent.rawResponseJSON ?? "") == (incoming.rawResponseJSON ?? "") else { return false }
        return true
    }

    func applyClear() {
        let count = items.count
        items.removeAll()
        Task.detached(priority: .utility) { [weak self] in
            await self?.cloudSync.auditNoticeCleared(count: count)
        }
    }

    func snapshotItems() -> [Notice] {
        items
    }

    func markServerListening() {
        serverRunning = true
        lastError = nil
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.cloudSync.auditServerStarted(port: self.port)
        }
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

    /// Opens a new Terminal.app window, registers it via `winid save`, and optionally chains a command.
    func initNewTerminal(chainCommand: String? = nil) async {
        WinidTerminalRunner.initNewTerminal(
            winidPath: winidExecutableURL?.path,
            chainCommand: chainCommand
        ) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success(let sessionId):
                    await self.upsertManualTerminalTrigger(sessionId)
                case .failure(let error):
                    self.switchStatus = .failed(error.message)
                    self.scheduleSwitchStatusClear(after: 5)
                }
            }
        }
    }

    /// Runs `winid open <id>` as a **Terminal.app** shell command (not from this process).
    /// Most ids come from agent sessions, but manual Terminal triggers can use any saved WINID.
    func openWinidSession(_ sessionIdRaw: String) {
        let id = sessionIdRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }

        // Per-session debounce: each session ID has its own 1-second cooldown.
        let now = Date()
        if let last = switchTimes[id], now.timeIntervalSince(last) < 1.0 { return }
        switchTimes[id] = now
        if switchTimes.count > 100 {
            let cutoff = now.addingTimeInterval(-120)
            switchTimes = switchTimes.filter { $0.value > cutoff }
        }

        switchStatus = .switching(id)
        switchStatusClearTask?.cancel()

        let switchStart = Date()
        Task.detached(priority: .utility) { [weak self] in
            await self?.cloudSync.auditSwitchAttempted(sessionId: id)
        }

        WinidTerminalRunner.openSession(
            sessionId: id,
            winidPath: winidExecutableURL?.path
        ) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let durationMs = Int(Date().timeIntervalSince(switchStart) * 1000)
                switch result {
                case .ok:
                    self.switchStatus = .succeeded(id)
                    self.scheduleSwitchStatusClear(after: 3)
                    // Capture window preview after a brief delay for the window to settle
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        self?.captureWindowPreview(sessionId: id)
                    }
                    Task.detached(priority: .utility) { [weak self] in
                        await self?.cloudSync.auditSwitchResult(sessionId: id, ok: true, error: nil, durationMs: durationMs)
                    }
                case .failed(let msg):
                    self.switchTimes.removeValue(forKey: id)
                    self.switchStatus = .failed(msg)
                    self.scheduleSwitchStatusClear(after: 5)
                    Task.detached(priority: .utility) { [weak self] in
                        await self?.cloudSync.auditSwitchResult(sessionId: id, ok: false, error: msg, durationMs: durationMs)
                    }
                }
            }
        }
    }

    /// Removes all notices for the given session and runs `winid remove` to unregister the window.
    func closeWinidSession(_ sessionIdRaw: String) {
        let id = sessionIdRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }

        items.removeAll { notice in
            guard let action = notice.action?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
            return action == id
        }

        switchTimes.removeValue(forKey: id)

        WinidTerminalRunner.removeSession(
            sessionId: id,
            winidPath: winidExecutableURL?.path
        )
    }

    private func scheduleSwitchStatusClear(after seconds: UInt64) {
        switchStatusClearTask?.cancel()
        switchStatusClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.switchStatus = .idle
        }
    }

    /// Captures a preview screenshot of the window for the given session ID.
    func captureWindowPreview(sessionId raw: String) {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }

        previewStatus = .loading
        previewImage = nil

        Task.detached(priority: .userInitiated) { [weak self] in
            let result = WindowPreviewCapture.capturePreview(sessionId: id)
            await MainActor.run { [weak self] in
                guard let self else { return }
                switch result {
                case .image(let img):
                    self.previewImage = img
                    self.previewStatus = .loaded(id)
                case .windowNotFound:
                    self.previewImage = nil
                    self.previewStatus = .notFound(id)
                case .permissionDenied:
                    self.previewImage = nil
                    self.previewStatus = .permissionNeeded
                case .noMetadata:
                    self.previewImage = nil
                    self.previewStatus = .notFound(id)
                }
            }
        }
    }

    func clearPreview() {
        previewImage = nil
        previewStatus = .idle
    }

    /// Merges remote history without overwriting notices already in memory.
    func hydrateFromCloud(_ remote: [Notice]) {
        let existingIds = Set(items.map { $0.id })
        let incoming = remote.filter { !existingIds.contains($0.id) }
        guard !incoming.isEmpty else { return }
        let merged = (items + incoming).sorted { $0.at > $1.at }
        items = Array(merged.prefix(maxItems))
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
