import Foundation
import SwiftUI
import OverprintKit

/// The two panes of the main window's mode rail.
enum EditorMode: String {
    case build = "Build"
    case write = "Write"
}

/// Which window content is showing.
enum Route {
    case launch
    case site
}

/// Top-level app state: routing between the launch window and the site shell, the current
/// site and its Write model, the preview server, and the persisted recents / launch preference.
@MainActor
final class AppModel: ObservableObject {
    @Published var route: Route = .launch
    @Published var currentSite: OpenSite?
    @Published var mode: EditorMode = .write
    @Published var recents: [RecentSite]
    @Published var showLaunchAtStart: Bool
    @Published var writeModel: WriteModel?
    @Published var buildModel: BuildModel?
    /// Example folders the user has dismissed from the launch window. The examples themselves are
    /// bundled and read only, so "delete" means hiding them from onboarding, remembered here.
    @Published var hiddenExamples: Set<String>

    let serverManager = ServerManager()
    let aiManager = AIManager()
    let gitManager = GitManager()

    private let store = RecentsStore()
    private let hiddenExamplesKey = "hiddenExamples.v1"
    private var watcher: FileWatcher?

    init() {
        recents = store.load()
        showLaunchAtStart = store.showLaunchAtStart
        hiddenExamples = Set(UserDefaults.standard.stringArray(forKey: "hiddenExamples.v1") ?? [])
    }

    func hideExample(_ folder: String) {
        hiddenExamples.insert(folder)
        UserDefaults.standard.set(Array(hiddenExamples), forKey: hiddenExamplesKey)
    }

    func restoreExamples() {
        hiddenExamples.removeAll()
        UserDefaults.standard.removeObject(forKey: hiddenExamplesKey)
    }

    /// Opens an existing site folder, builds and serves it, and routes to Write mode.
    /// Throws if it is not a valid site.
    func openSite(at url: URL) throws {
        let site = try OpenSite.load(url: url)
        mount(url: url, site: site, serve: true, initialMode: .write)
    }

    /// Scaffolds a fresh empty site and routes to Build mode's empty state. The preview server
    /// stays stopped until the assistant runs its first build.
    func createSite(at url: URL) throws {
        try SiteScaffolder().scaffold(at: url, title: url.lastPathComponent)
        let site = try OpenSite.load(url: url)
        mount(url: url, site: site, serve: false, initialMode: .build)
    }

    private func mount(url: URL, site: OpenSite, serve: Bool, initialMode: EditorMode) {
        currentSite = site
        mode = initialMode
        recents = store.record(url: url, name: site.config.title)

        let write = WriteModel(site: url, serverManager: serverManager)
        write.load()
        if serve { write.startServing() }
        writeModel = write

        let build = BuildModel(site: url, serverManager: serverManager, ai: aiManager)
        buildModel = build

        watcher?.stop()
        // Theme and static changes alter the built site exactly as content changes do, so the
        // preview has to reload for them too. dist/ is deliberately NOT watched: the build writes
        // it, which would retrigger the build.
        let watched = ["content", "theme", "static"].map(url.appendingPathComponent)
        let newWatcher = FileWatcher(paths: watched) { [weak write, weak build] in
            DispatchQueue.main.async {
                write?.externalChange()
                build?.bumpPreview()
            }
        }
        newWatcher.start()
        watcher = newWatcher

        Task { await gitManager.refresh(site: url) }
        route = .site
    }

    func closeSite() {
        watcher?.stop()
        watcher = nil
        writeModel?.saveNow()
        writeModel?.settleFilename()
        serverManager.stop()
        writeModel = nil
        buildModel = nil
        currentSite = nil
        route = .launch
    }

    func clearRecents() {
        recents = store.clear()
    }

    func removeRecent(_ recent: RecentSite) {
        recents = store.remove(path: recent.path)
    }

    func setShowLaunchAtStart(_ value: Bool) {
        showLaunchAtStart = value
        store.showLaunchAtStart = value
    }
}
