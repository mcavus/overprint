import Foundation

/// Creates a fresh, valid (empty) Overprint site: `content/posts/` plus a minimal
/// `overprint.yml`. Used by the app's "Create a new site" and the CLI `init`.
public struct SiteScaffolder {
    public init() {}

    @discardableResult
    public func scaffold(at siteURL: URL, title: String) throws -> URL {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: siteURL.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        } catch {
            throw OverprintError.io("could not create site folders: \(error.localizedDescription)")
        }

        let configURL = siteURL.appendingPathComponent("overprint.yml")
        if !fm.fileExists(atPath: configURL.path) {
            let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let config = SiteConfig(
                title: name.isEmpty ? "My Site" : name,
                author: "",
                description: "",
                theme: SiteTheme()
            )
            try config.save(to: configURL)
        }

        // Drop in the contract document so an agent (or a human) landing in this folder knows
        // the frontmatter rules without needing Overprint itself.
        let agentsURL = siteURL.appendingPathComponent("AGENTS.md")
        if !fm.fileExists(atPath: agentsURL.path), let template = Self.agentsTemplate() {
            try? template.write(to: agentsURL, atomically: true, encoding: .utf8)
        }
        return siteURL
    }

    /// The bundled AGENTS.md template, or nil if the resource is unavailable.
    static func agentsTemplate() -> String? {
        guard let url = Bundle.module.resourceURL?
            .appendingPathComponent("Scaffold")
            .appendingPathComponent("AGENTS.md")
        else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
