import Foundation

/// Runs `winid open <sessionId>` through a shell command.
/// `winid open` itself performs the AppleScript focus, so opening a new Terminal window is unnecessary.
enum WinidTerminalRunner {
    enum OpenResult: Sendable {
        case ok
        case failed(String)
    }

    struct CommandError: LocalizedError {
        let message: String

        var errorDescription: String? { message }
    }

    /// Runs `winid remove <sessionId>` to unregister the window.
    static func removeSession(
        sessionId raw: String,
        winidPath: String?,
        completion: (@Sendable (OpenResult) -> Void)? = nil
    ) {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            completion?(.failed("Empty session ID"))
            return
        }
        let path = winidPath

        Task.detached {
            do {
                _ = try await runWinidCommand(subcommand: "remove", arguments: [id], winidPath: path)
                completion?(.ok)
            } catch {
                let msg = error.localizedDescription
                fputs("agm: winid remove failed: \(msg)\n", stderr)
                completion?(.failed(msg))
            }
        }
    }

    /// `winidPath`: resolved script path, or `nil` to invoke `winid` via login shell (`PATH` from login profiles, etc.).
    static func openSession(
        sessionId raw: String,
        winidPath: String?,
        completion: (@Sendable (OpenResult) -> Void)? = nil
    ) {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            completion?(.failed("Empty session ID"))
            return
        }
        let path = winidPath

        Task.detached {
            // Brief yield so AppKit finishes the button/scroll click handling before Terminal focus runs.
            try? await Task.sleep(nanoseconds: 16_000_000)
            do {
                var output: String
                do {
                    output = try await runWinidCommand(subcommand: "open", arguments: [id], winidPath: path)
                } catch {
                    // One automatic retry after 500ms
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    output = try await runWinidCommand(subcommand: "open", arguments: [id], winidPath: path)
                }
                // winid exits 0 on success; exit 2 means "window not found" (handled by throw below).
                // Check output for "Warning:" as extra safety in case exit-code fix hasn't propagated.
                if output.contains("Warning:") {
                    let msg = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    fputs("agm: winid open warning: \(msg)\n", stderr)
                    completion?(.failed(msg))
                } else {
                    completion?(.ok)
                }
            } catch {
                let msg = error.localizedDescription
                fputs("agm: winid open failed: \(msg)\n", stderr)
                completion?(.failed(msg))
            }
        }
    }

    /// Opens a brand-new Terminal.app window, runs `winid save <sessionId>` inside it,
    /// then optionally chains an additional command (e.g. `claude`, `cursor agent`).
    /// Returns the generated session ID on success.
    static func initNewTerminal(
        winidPath: String?,
        chainCommand: String? = nil,
        completion: (@Sendable (Result<String, CommandError>) -> Void)? = nil
    ) {
        let sessionId = "manual-\(UUID().uuidString.prefix(8).lowercased())"
        var shellCmd: String
        if let p = winidPath?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            shellCmd = "\(shellQuoted(p)) save \(shellQuoted(sessionId))"
        } else {
            shellCmd = "winid save \(shellQuoted(sessionId))"
        }
        if let chain = chainCommand?.trimmingCharacters(in: .whitespacesAndNewlines), !chain.isEmpty {
            shellCmd += " && \(chain)"
        }

        Task.detached {
            do {
                // Use AppleScript to open a new Terminal window and run winid save (+ optional command) in it.
                let escapedCmd = shellCmd.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                let script = """
                tell application "Terminal"
                    activate
                    set newWindow to do script "\(escapedCmd)"
                end tell
                """
                let proc = Process()
                let outPipe = Pipe()
                let errPipe = Pipe()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                proc.arguments = ["-e", script]
                proc.standardOutput = outPipe
                proc.standardError = errPipe
                try proc.run()
                proc.waitUntilExit()

                if proc.terminationStatus != 0 {
                    let errText = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    throw CommandError(message: errText.isEmpty ? "Failed to open Terminal window" : errText)
                }
                completion?(.success(sessionId))
            } catch let error as CommandError {
                fputs("agm: initNewTerminal failed: \(error.message)\n", stderr)
                completion?(.failure(error))
            } catch {
                let ce = CommandError(message: error.localizedDescription)
                fputs("agm: initNewTerminal failed: \(ce.message)\n", stderr)
                completion?(.failure(ce))
            }
        }
    }

    @discardableResult
    private static func runWinidCommand(subcommand: String, arguments: [String], winidPath: String?) async throws -> String {
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

        // 8-second hard timeout: race between process completion and timeout deadline.
        let didFinish: Bool = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    p.terminationHandler = { _ in c.resume() }
                }
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            if !first {
                p.terminate()
                for await _ in group {}
            }
            return first
        }

        if !didFinish {
            throw CommandError(message: "winid timed out after 8 seconds")
        }

        let out = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let combined = [err, out]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""

        if p.terminationStatus != 0 {
            throw CommandError(message: combined.isEmpty ? "Couldn't reach that Terminal session." : combined)
        }

        return out
    }

    private static func shellQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
