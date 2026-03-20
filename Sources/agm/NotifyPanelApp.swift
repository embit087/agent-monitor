import AppKit
import SwiftUI

private enum AppActivationSupport {
    private static var promotedFromProhibited = false

    static func prepareForInteractiveUse() {
        let app = NSApplication.shared
        guard app.activationPolicy() == .prohibited else { return }
        promotedFromProhibited = app.setActivationPolicy(.accessory)
    }

    static func activateWindowIfNeeded() {
        guard promotedFromProhibited else { return }
        DispatchQueue.main.async {
            let app = NSApplication.shared
            app.activate(ignoringOtherApps: true)
            app.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
}

@main
struct NotifyPanelApp: App {
    @StateObject private var model = PanelModel()

    init() {
        AppActivationSupport.prepareForInteractiveUse()
    }

    var body: some Scene {
        WindowGroup("Agent Monitor") {
            ContentView()
                .environmentObject(model)
                .onAppear {
                    AppActivationSupport.activateWindowIfNeeded()
                    // UNUserNotificationCenter must run after the app is up on the main run loop
                    // (calling it from App.init() raises NSException on some macOS versions).
                    SystemNotificationSupport.shared.configure()
                    model.startServerIfNeeded()
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 560, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
