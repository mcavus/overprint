import SwiftUI
import AppKit

@main
struct OverprintApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var updater = UpdaterController()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    static let mainWindowID = "overprint-main"

    init() {
        Fonts.registerBundled()
    }

    var body: some Scene {
        Window("Overprint", id: Self.mainWindowID) {
            RootView()
                .environmentObject(model)
                // Hand the reopen action to the delegate, so clicking the Dock icon can bring the
                // window back. Without it, closing the only window strands the app with no UI.
                .onAppear { AppDelegate.reopenMainWindow = { openWindow(id: Self.mainWindowID) } }
        }
        .windowStyle(.hiddenTitleBar)
        // .contentSize pins the window to its content's fixed frame, which also greys out zoom and
        // full screen. The content now states a minimum instead, so the window is free above it.
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
            // This is a single Window scene: nothing recreates it once closed, and macOS remembers
            // the closed state across launches. This menu item is the way back.
            CommandGroup(after: .windowList) {
                Button("Overprint Window") { openWindow(id: Self.mainWindowID) }
                    .keyboardShortcut("0", modifiers: .command)
            }
        }

        Settings {
            SettingsView(ai: model.aiManager, updater: updater)
                .environmentObject(model)
        }
    }
}

/// Restores the main window when the app is activated with no windows open, which is what clicking
/// the Dock icon does. A single-window app without this looks like it failed to launch.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the main scene once it has appeared.
    static var reopenMainWindow: (() -> Void)?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        restore()
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // State restoration can start the app with its window closed, so make sure launching
        // always ends up showing something.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) else { return }
            self?.restore()
        }
    }

    private func restore() {
        if let existing = NSApp.windows.first(where: { $0.canBecomeMain }) {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        Self.reopenMainWindow?()
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Swaps the window's content between the launch window and the site shell.
private struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        switch model.route {
        case .launch:
            LaunchView()
        case .site:
            MainWindowView()
        }
    }
}
