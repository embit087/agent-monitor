import Foundation

/// Resolves a focus target id: optional overrides, Claude Code session id (if exported), Fish `WINID_SESSION_UUID`, then `winid session`.
enum WinidSessionId {
    static func resolve(
        environment env: [String: String] = ProcessInfo.processInfo.environment,
        winidExecutable: URL?
    ) -> String? {
        if let o = trim(env["NOTIFY_MAILBOX_TEST_SESSION"]) { return o }
        if let c = trim(env["CLAUDE_CODE_SESSION_ID"]) { return c }
        if let u = trim(env["WINID_SESSION_UUID"]) { return u }
        guard let exe = winidExecutable else { return nil }
        return runWinidSession(exe: exe, environment: env)
    }

    private static func trim(_ v: String?) -> String? {
        guard let v else { return nil }
        let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func runWinidSession(exe: URL, environment: [String: String]) -> String? {
        let p = Process()
        p.executableURL = exe
        p.arguments = ["session"]
        p.environment = environment
        let outPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = Pipe()
        do {
            try p.run()
        } catch {
            return nil
        }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trim(s)
    }
}
