import Foundation

/// The theme used for a build: Stencil templates (keyed by name for a `DictionaryLoader`), the
/// stylesheet, and any extra asset files that belong in `dist/assets/`.
///
/// A site may override any of it. `load(siteURL:)` starts from the bundled theme and overlays what
/// the site carries in `theme/`, ONE FILE AT A TIME: overriding `base.html` does not oblige you to
/// vendor the other templates, and a file you leave out keeps falling back to the bundled one.
struct Theme {
    let templates: [String: String]
    let styleCSS: String
    /// Files from the site's `theme/assets/` other than `style.css`, keyed by path relative to that
    /// directory. Copied into `dist/assets/`, so a stylesheet can reference them relatively.
    let extraAssets: [String: URL]
    /// What this site overrode, for `overprint validate` to report back.
    let overriddenNames: [String]

    /// Every template the engine renders or includes. A file in `theme/templates/` outside this set
    /// is a typo, which would otherwise sit there having no effect at all.
    static let templateNames = [
        "base.html", "index.html", "post.html", "tag.html",
        "page.html", "nav.html", "404.html", "head.html",
    ]

    /// What an overridden `base.html` has to keep. Each of these breaks silently when dropped,
    /// which is the trap a vendored template sets.
    static let baseRequirements: [(needle: String, why: String)] = [
        ("{% block head_top %}", "the 404 page emits its <base href> here; without it, every relative link on that page resolves against whatever address the visitor mistyped"),
        ("{% block title %}", "every page would carry the same title"),
        ("{% block content %}", "every page would render empty"),
        ("{{ theme.rootStyle }}", "the :root block carrying --accent, --paper and --display would stop being emitted"),
    ]

    static func bundledRoot() throws -> URL {
        guard let root = Bundle.module.resourceURL?.appendingPathComponent("Theme") else {
            throw OverprintError.templateError("bundled theme resources are missing")
        }
        return root
    }

    /// Loads the bundled theme, overlaid with whatever the site overrides. Pass nil for bundled-only.
    static func load(siteURL: URL?) throws -> Theme {
        let root = try bundledRoot()
        let bundledTemplates = root.appendingPathComponent("templates")

        func read(_ url: URL) throws -> String {
            do {
                return try String(contentsOf: url, encoding: .utf8)
            } catch {
                throw OverprintError.templateError(
                    "could not read \(url.lastPathComponent): \(error.localizedDescription)"
                )
            }
        }

        var templates: [String: String] = [:]
        for name in templateNames {
            templates[name] = try read(bundledTemplates.appendingPathComponent(name))
        }
        var css = try read(root.appendingPathComponent("assets/style.css"))
        var extraAssets: [String: URL] = [:]
        var overridden: [String] = []

        guard let siteURL else {
            return Theme(templates: templates, styleCSS: css, extraAssets: [:], overriddenNames: [])
        }

        let themeDir = siteURL.appendingPathComponent("theme")
        let fm = FileManager.default

        let localTemplates = themeDir.appendingPathComponent("templates")
        if let names = try? fm.contentsOfDirectory(atPath: localTemplates.path) {
            for name in names.sorted() where !name.hasPrefix(".") {
                if let issue = templateNameIssue(name) { throw issue }
                templates[name] = try read(localTemplates.appendingPathComponent(name))
                overridden.append(name)
            }
        }

        for (relative, url) in regularFiles(under: themeDir.appendingPathComponent("assets")) {
            if relative == "style.css" {
                css = try read(url)
                overridden.append("assets/style.css")
            } else {
                extraAssets[relative] = url
            }
        }

        return Theme(
            templates: templates,
            styleCSS: css,
            extraAssets: extraAssets,
            overriddenNames: overridden.sorted()
        )
    }

    /// Every regular file under `root`, keyed by its path relative to `root`.
    ///
    /// Both sides are symlink-resolved before comparing. On macOS the temp directory is `/var`,
    /// a symlink to `/private/var`, and a directory enumerator hands back the resolved spelling
    /// while the root URL keeps the one it was built from. Comparing them raw matches nothing and
    /// the whole directory silently reads as empty.
    static func regularFiles(under root: URL) -> [String: URL] {
        let fm = FileManager.default
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        guard fm.fileExists(atPath: root.path),
              let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
        else { return [:] }

        var found: [String: URL] = [:]
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }
            let filePath = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard filePath.hasPrefix(rootPath + "/") else { continue }
            let relative = String(filePath.dropFirst(rootPath.count + 1))
            if relative.hasPrefix(".") || relative.contains("/.") { continue }
            found[relative] = url
        }
        return found
    }

    /// Rejects a file in `theme/templates/` that the engine will never render, so a typo announces
    /// itself instead of quietly doing nothing.
    static func templateNameIssue(_ name: String) -> OverprintError? {
        // Underscore-prefixed files are the author's own partials, included by hand.
        if name.hasPrefix("_") { return nil }
        guard !templateNames.contains(name) else { return nil }
        return .templateError(
            "theme/templates/\(name) is not a template Overprint renders, so it would have no "
            + "effect. Expected one of: \(templateNames.joined(separator: ", ")). "
            + "For your own partials, start the name with an underscore and include them yourself."
        )
    }
}
