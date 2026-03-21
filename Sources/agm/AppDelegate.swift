import AppKit

/// Prevents the app from quitting when the last window is closed.
/// The HTTP server must keep running so agent hooks can still POST notifications.
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
