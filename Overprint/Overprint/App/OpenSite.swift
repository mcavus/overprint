import Foundation
import OverprintKit

/// A site currently open in the app: its folder, loaded config, and post count.
/// Loading goes through OverprintKit, so this is the app's link to the engine.
struct OpenSite {
    let url: URL
    let config: SiteConfig
    let postCount: Int

    var displayName: String {
        config.title.isEmpty ? url.lastPathComponent : config.title
    }

    /// Loads a site folder. Throws if there is no valid `overprint.yml`.
    static func load(url: URL) throws -> OpenSite {
        let store = SiteStore(siteURL: url)
        let config = try store.loadConfig()
        let count = (try? store.loadPosts().count) ?? 0
        return OpenSite(url: url, config: config, postCount: count)
    }
}
