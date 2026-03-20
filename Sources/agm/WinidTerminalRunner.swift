import Foundation

/// Runs `winid open <sessionId>` through a shell command.
/// `winid open` itself performs the AppleScript focus, so opening a new Terminal window is unnecessary.
enum WinidTerminalRunner {
    struct CommandError: LocalizedError {
        let message: String

        var errorDescription: String? { message }
    }

    /// `winidPath`: resolved script path, or `nil` to invoke `winid` via login shell (`PATH` from login profiles, etc.).
    static func openSession(sessionId raw: String, winidPath: String?) {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        let path = winidPath

        Task.detached {
            // Brief yield so AppKit finishes the button/scroll click handling before Terminal focus runs.
            try? await Task.sleep(nanoseconds: 60_000_000)
            _ = try? runWinidCommand(subcommand: "open", arguments: [id], winidPath: path)
        }
    }

    @discardableResult
    private static func runWinidCommand(subcommand: String, arguments: [String], winidPath: String?) throws -> String {
        let explicitWinid: String? = {
            guard let p = winidPath?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty else {
                return nil
            }
            return p
        }()

        let joinedArguments = arguments.map(shellQuoted).joined(separator: " ")
        let command: String
        let args: [String]
        if let explicitWinid {
            command = "\(shellQuoted(explicitWinid)) \(subcommand) \(joinedArguments)"
            args = ["-lc", command]
        } else {
            command = "winid \(subcommand) \(joinedArguments)"
            args = ["-ilc", command]
        }

        let p = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = args
        p.standardOutput = stdout
        p.standardError = stderr
        try p.run()
        p.waitUntilExit()

        let out = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let combined = [err, out]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""

        if p.terminationStatus != 0 {
            throw CommandError(message: combined.isEmpty ? "Couldn’t reach that Terminal session." : combined)
        }

        return out
    }

    private static func shellQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
