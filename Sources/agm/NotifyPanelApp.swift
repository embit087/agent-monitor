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
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var model = PanelModel()
    @StateObject private var notepadModel = NotepadModel()
    @StateObject private var projectModel = ProjectGroupModel()

    init() {
        AppActivationSupport.prepareForInteractiveUse()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(notepadModel)
                .environmentObject(projectModel)
                .onAppear {
                    AppActivationSupport.activateWindowIfNeeded()
                    // UNUserNotificationCenter must run after the app is up on the main run loop
                    // (calling it from App.init() raises NSException on some macOS versions).
                    SystemNotificationSupport.shared.configure()
                    model.startServerIfNeeded(notepad: notepadModel)
                    // Background history hydration — non-blocking, merges cloud history into local state
                    Task {
                        let history = await model.cloudSync.loadHistory()
                        if !history.isEmpty {
                            await MainActor.run { model.hydrateFromCloud(history) }
                        }
                    }
                    // Audit app.started
                    Task.detached(priority: .utility) {
                        await model.cloudSync.auditAppStarted()
                    }
                }
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 560, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Window("Notepad", id: "notepad") {
            NotepadView()
                .environmentObject(notepadModel)
        }
        .defaultSize(width: 800, height: 600)
    }
}
