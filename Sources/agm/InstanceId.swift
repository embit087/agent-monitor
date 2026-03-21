import Foundation

/// Persistent UUID stored at `~/.agm/instance-id` (created on first run).
/// Tags every notice and audit event with the originating machine.
enum InstanceId {
    static let current: String = resolve()

    private static func resolve() -> String {
        let file = agmDir().appendingPathComponent("instance-id")
        if let existing = try? String(contentsOf: file, encoding: .utf8) {
            let t = existing.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, UUID(uuidString: t) != nil { return t }
        }
        try? FileManager.default.createDirectory(at: agmDir(), withIntermediateDirectories: true)
        let fresh = UUID().uuidString
        try? fresh.write(to: file, atomically: true, encoding: .utf8)
        return fresh
    }

    static func agmDir() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let p = env["AGM_PREFIX"]?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            return URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".agm")
    }
}
