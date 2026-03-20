import Foundation

/// Finds the `winid` script without requiring `NOTIFY_MAILBOX_WINID` when common layouts match.
enum WinidLocator {
    /// `Sources/agm` → package root → parent (`tools`) → `winid`.
    private static var repoAdjacentWinid: URL {
        let here = URL(fileURLWithPath: #filePath, isDirectory: false)
        let pkgRoot = here.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return pkgRoot.deletingLastPathComponent().appendingPathComponent("winid")
    }

    static func resolve(environment env: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        var paths: [String] = []
        if let v = trim(env["NOTIFY_MAILBOX_WINID"]) { paths.append(v) }
        if let v = trim(env["WINID_SCRIPT"]) { paths.append(v) }
        paths.append("\(NSHomeDirectory())/embitious/tools/winid")
        paths.append("\(NSHomeDirectory())/tools/winid")
        paths.append(repoAdjacentWinid.path)

        for raw in paths {
            let path = (raw as NSString).expandingTildeInPath
            guard !path.isEmpty else { continue }
            let url = URL(fileURLWithPath: path)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private static func trim(_ s: String?) -> String? {
        guard let s else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
