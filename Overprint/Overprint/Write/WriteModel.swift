import Foundation
import SwiftUI
import OverprintKit

/// Drives Write mode: the posts list, the editor buffer, autosave, and the build → reload
/// loop that keeps the live preview in sync. One instance per open site.
@MainActor
final class WriteModel: ObservableObject {
    let site: URL

    @Published private(set) var posts: [LoadedPost] = []
    @Published var selectedURL: URL?
    @Published var editorText: String = ""
    @Published private(set) var isDirty = false
    /// The most recent load, save, or build failure, for the Write header to show. Previously
    /// these were NSLog-only, which made a broken site look identical to a healthy one.
    @Published private(set) var lastError: String?
    /// Bumped whenever the preview should reload; observed by PreviewWebView.
    @Published private(set) var reloadToken = 0

    private let serverManager: ServerManager
    private var autosaveWork: DispatchWorkItem?
    private var rebuildWork: DispatchWorkItem?

    var distURL: URL { site.appendingPathComponent("dist") }

    var selectedPost: LoadedPost? {
        posts.first { $0.sourceURL == selectedURL }
    }

    init(site: URL, serverManager: ServerManager) {
        self.site = site
        self.serverManager = serverManager
    }

    // MARK: Loading

    func load() {
        refreshPosts()
        if selectedURL == nil { selectedURL = posts.first?.sourceURL }
        loadEditorFromDisk()
    }

    private func refreshPosts() {
        let loaded: [LoadedPost]
        do {
            loaded = try SiteStore(siteURL: site).loadPosts()
        } catch {
            // `loadPosts` throws on the FIRST invalid post, so substituting [] here would treat
            // one bad frontmatter block as "this site has no posts": the list empties, the
            // selection goes nil, and every later autosave silently no-ops. Keep what we have.
            lastError = Self.describe(error)
            return
        }
        lastError = nil
        posts = loaded

        guard let selected = selectedURL else {
            // Posts appeared while nothing was selected (a fresh site, or Build just generated
            // them). Adopt the newest so typing is never discarded.
            if let first = loaded.first {
                selectedURL = first.sourceURL
                loadEditorFromDisk()
            }
            return
        }

        if !loaded.contains(where: { $0.sourceURL == selected }) {
            // The selected file vanished (renamed in Finder, rewritten by the Build assistant).
            // Retarget, but never leave the buffer pointing at the old post: the next autosave
            // would write post A's text into post B's file.
            autosaveWork?.cancel()
            autosaveWork = nil
            isDirty = false
            selectedURL = loaded.first?.sourceURL
            loadEditorFromDisk()
        }
    }

    private static func describe(_ error: Error) -> String {
        (error as? OverprintError)?.description ?? error.localizedDescription
    }

    private func loadEditorFromDisk() {
        guard let post = selectedPost else { editorText = ""; return }
        editorText = (try? String(contentsOf: post.sourceURL, encoding: .utf8)) ?? post.body
        isDirty = false
    }

    // MARK: Selection

    func select(_ url: URL) {
        guard url != selectedURL else { return }
        if isDirty { saveNow() }
        selectedURL = url
        loadEditorFromDisk()
        reloadToken += 1
    }

    func newPost() {
        if isDirty { saveNow() }
        do {
            let url = try PostWriter().createPost(in: site, title: "Untitled")
            refreshPosts()
            selectedURL = url
            loadEditorFromDisk()
            rebuildAndReload()
        } catch {
            NSLog("Overprint: new post failed: \(error.localizedDescription)")
        }
    }

    // MARK: Editing / autosave

    /// Called by the editor on a user edit (the buffer is already updated via the binding).
    func userDidEdit() {
        isDirty = true
        autosaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        autosaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// The post body with frontmatter split off, for the inline copilot.
    func currentBody() -> String {
        FrontmatterParser().split(editorText).body
    }

    /// Replaces the body with copilot output, preserving frontmatter, then triggers autosave.
    func applyEditedBody(_ newBody: String) {
        let (yaml, _) = FrontmatterParser().split(editorText)
        if let yaml {
            editorText = "---\n\(yaml)\n---\n\n\(newBody)\n"
        } else {
            editorText = newBody
        }
        userDidEdit()
    }

    func saveNow() {
        autosaveWork?.cancel()
        autosaveWork = nil
        // Write to the retained selectedURL, NOT through selectedPost. selectedPost resolves via
        // the `posts` list, so a single unparseable post used to make saving impossible even
        // though the file being edited was perfectly fine.
        guard isDirty, let target = selectedURL else { return }
        do {
            try editorText.write(to: target, atomically: true, encoding: .utf8)
            isDirty = false
            lastError = nil
            scheduleRebuild()
        } catch {
            lastError = "Could not save \(target.lastPathComponent): \(Self.describe(error))"
            NSLog("Overprint: autosave failed: \(error.localizedDescription)")
        }
    }

    // MARK: Build + preview

    private func scheduleRebuild() {
        rebuildWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.rebuildAndReload() }
        rebuildWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    func rebuildAndReload() {
        rebuildWork?.cancel()
        rebuildWork = nil
        do {
            try SiteBuilder().build(siteURL: site)
            lastError = nil
        } catch {
            lastError = Self.describe(error)
            NSLog("Overprint: build failed: \(error.localizedDescription)")
        }
        refreshPosts()
        reloadToken += 1
    }

    /// Triggered by the FileWatcher for changes made outside the editor. Rebuilds and reloads
    /// the preview without touching the editor buffer.
    func externalChange() {
        scheduleRebuild()
    }

    // MARK: Serving

    func startServing() {
        do {
            try SiteBuilder().build(siteURL: site)
        } catch {
            NSLog("Overprint: build failed: \(error.localizedDescription)")
        }
        serverManager.start(dist: distURL)
        reloadToken += 1
    }

    func stopServing() {
        serverManager.stop()
    }

    func toggleServing() {
        if serverManager.isServing {
            stopServing()
        } else {
            startServing()
        }
    }
}
