import Foundation

/// Finds the `winid` script via environment variables, the installed prefix, standard locations,
/// or the repo-adjacent development layout.
enum WinidLocator {
    /// `Sources/agm` → package root → parent (`tools`) → `winid`.
    private static var repoAdjacentWinid: URL {
        let here = URL(fileURLWithPath: #filePath, isDirectory: false)
        let pkgRoot = here.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return pkgRoot.deletingLastPathComponent().appendingPathComponent("winid")
    }

    static func resolve(environment env: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        var paths: [String] = []

        // 1. Explicit env overrides
        if let v = trim(env["NOTIFY_MAILBOX_WINID"]) { paths.append(v) }
        if let v = trim(env["WINID_SCRIPT"]) { paths.append(v) }

        // 2. Installed prefix: AGM_PREFIX/bin/winid (default ~/.agm)
        let prefix = trim(env["AGM_PREFIX"]) ?? "\(NSHomeDirectory())/.agm"
        paths.append("\(prefix)/bin/winid")

        // 3. Standard locations
        paths.append("\(NSHomeDirectory())/.local/bin/winid")
        paths.append("/usr/local/bin/winid")

        // 4. Repo-adjacent fallback (development)
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
