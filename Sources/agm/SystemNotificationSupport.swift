import Foundation
import UserNotifications

/// Posts macOS banner notifications for each inbox item (same payload as `POST /api/notify`).
/// Disable with `NOTIFY_MAILBOX_NO_SYSTEM_NOTIFY=1`.
///
/// `UNUserNotificationCenter` only works inside a real `.app` bundle. `swift run` builds a bare
/// binary under `.build/.../debug/`, which has no bundle proxy — Apple aborts if you touch UN there.
/// In that case we fall back to `osascript display notification`.
final class SystemNotificationSupport: NSObject, UNUserNotificationCenterDelegate {
    static let shared = SystemNotificationSupport()

    private let lock = NSLock()
    private var didConfigure = false

    /// True when running from a packaged application (not `swift run` / CLI build output).
    private static var hasAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }

    private let useUserNotificationCenter: Bool = SystemNotificationSupport.hasAppBundle

    private override init() {
        super.init()
    }

    func configure() {
        lock.lock()
        if didConfigure {
            lock.unlock()
            return
        }
        didConfigure = true
        lock.unlock()

        guard useUserNotificationCenter else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    static func shouldPost() -> Bool {
        let v = ProcessInfo.processInfo.environment["NOTIFY_MAILBOX_NO_SYSTEM_NOTIFY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return v != "1" && v != "true" && v != "yes"
    }

    static func postNotice(_ notice: Notice) {
        guard shouldPost() else { return }
        if shared.useUserNotificationCenter {
            postUserNotification(notice)
        } else {
            postAppleScriptNotification(notice)
        }
    }

    private static func postUserNotification(_ notice: Notice) {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.summary ?? notice.body
        if let s = notice.source, !s.isEmpty {
            content.subtitle = s
        }
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: notice.id.uuidString,
            content: content,
            trigger: nil
        )
        DispatchQueue.main.async {
            UNUserNotificationCenter.current().add(request)
        }
    }

    /// `display notification` via osascript — works for SPM / non-bundle executables.
    private static func postAppleScriptNotification(_ notice: Notice) {
        let title = appleScriptLiteral(String(notice.title.prefix(200)))
        let body = appleScriptLiteral(String((notice.summary ?? notice.body).prefix(800)))
        var script = "display notification \"\(body)\" with title \"\(title)\""
        if let s = notice.source?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            script += " subtitle \"\(appleScriptLiteral(String(s.prefix(120))))\""
        }
        script += " sound name \"Glass\""
        Task.detached(priority: .utility) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", script]
            try? p.run()
            p.waitUntilExit()
        }
    }

    private static func appleScriptLiteral(_ s: String) -> String {
        s
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
