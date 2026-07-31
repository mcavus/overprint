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
                .background(WindowConfigurator(route: model.route))
                // Xcode-style: the close button ends the session, not the app. The window goes
                // away and the app keeps running, so the next Dock click lands on the launch
                // window rather than back in the site that was just closed. Handing this to the
                // app delegate rather than a view keeps it installed for the app's lifetime.
                .onAppear {
                    AppDelegate.willCloseWindow = { [weak model] in
                        guard let model, model.route == .site else { return }
                        model.closeSite()
                    }
                }
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

/// Keeps the window's sizing in step with what it is showing.
///
/// The launch window is a fixed piece of layout; letting it stretch just floats it in an empty
/// field. A site, by contrast, has to be resizable, zoomable and able to go full screen, which
/// means the resizable style mask has to come back on when a site opens.
private struct WindowConfigurator: NSViewRepresentable {
    let route: Route

    private static let launchSize = NSSize(width: 760, height: 474)
    private static let siteMinSize = NSSize(width: 900, height: 560)
    private static let siteDefaultSize = NSSize(width: 1160, height: 724)

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let route = self.route
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            AppDelegate.claimMainWindow(window)
            switch route {
            case .launch:
                window.styleMask.remove(.resizable)
                window.contentMinSize = Self.launchSize
                window.contentMaxSize = Self.launchSize
                // Both are the launch size, so order is harmless here, but the window still has to
                // be told to shrink: a site-sized frame does not follow a smaller maximum on its own.
                if window.contentLayoutRect.size != Self.launchSize {
                    window.setContentSize(Self.launchSize)
                }
            case .site:
                window.styleMask.insert(.resizable)
                // Lift the ceiling before raising the floor: a minimum larger than the maximum
                // still in force from the launch window leaves AppKit clamping the window to
                // launch size.
                window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                               height: CGFloat.greatestFiniteMagnitude)
                window.contentMinSize = Self.siteMinSize
                // contentMinSize does not grow a window that is already smaller, and coming from
                // the launch window it always is.
                let current = window.frame.size
                if current.width < Self.siteDefaultSize.width || current.height < Self.siteDefaultSize.height {
                    window.setContentSize(Self.siteDefaultSize)
                    window.center()
                }
            }
        }
    }
}

/// Restores the main window when the app is activated with no windows open, which is what clicking
/// the Dock icon does. A single-window app without this looks like it failed to launch.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    /// Set by the main scene once it has appeared.
    static var reopenMainWindow: (() -> Void)?
    /// Runs as the window closes, to tear down whatever the window was showing. The close is never
    /// vetoed: the window goes away and the app stays running.
    static var willCloseWindow: (() -> Void)?

    /// The window the main scene lives in. Settings opens a second window that also reports
    /// canBecomeMain, so every piece of window handling below has to name which one it means.
    private static weak var mainWindow: NSWindow?

    /// Whatever delegate SwiftUI installed. Unhandled messages are forwarded to it.
    private weak var previousDelegate: NSWindowDelegate?

    /// Called by the main scene once its window exists.
    static func claimMainWindow(_ window: NSWindow) {
        mainWindow = window
        (NSApp.delegate as? AppDelegate)?.adopt(window)
    }

    /// Closing the last window must not end the app: the Dock icon is how you get back to the
    /// launch window and pick another site.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as AnyObject? === Self.mainWindow else { return }
        Self.willCloseWindow?()
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (previousDelegate?.responds(to: selector) ?? false)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        super.responds(to: selector) ? nil : previousDelegate
    }

    /// Installs this object as the main window's delegate. `previousDelegate` holds exactly one
    /// window's delegate, so this must never adopt a second window: Settings would overwrite it and
    /// the main window would forward its unhandled messages to the Settings delegate.
    private func adopt(_ window: NSWindow) {
        guard window === Self.mainWindow, window.delegate !== self else { return }
        previousDelegate = window.delegate
        window.delegate = self
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        restore()
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            self?.adopt(window)
        }

        // State restoration can start the app with its window closed, so make sure launching
        // always ends up showing something.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard Self.mainWindow?.isVisible != true else { return }
            self?.restore()
        }
    }

    private func restore() {
        if let existing = Self.mainWindow {
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
