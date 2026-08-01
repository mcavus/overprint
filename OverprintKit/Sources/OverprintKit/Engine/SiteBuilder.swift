import Foundation
import Stencil

/// The result of a build: how many posts were written and where.
public struct BuildSummary: Equatable, Sendable {
    public var postCount: Int
    public var outputURL: URL
}

/// The build pipeline: load the site, render each post and the index through Stencil, and
/// write a flat `dist/` (`index.html`, `<slug>.html` per post, `assets/style.css`) with
/// relative links so the output opens directly over `file://`.
public struct SiteBuilder {
    public init() {}

    /// Builds the site into `dist/`.
    ///
    /// `includeDrafts` keeps `draft: true` posts in the pages and index; the RSS feed, sitemap, and
    /// tag pages exclude drafts either way.
    ///
    /// It defaults to FALSE, so output is publishable unless a caller opts in. It used to default to
    /// true, which meant a forgotten argument published the author's unfinished writing: a draft got
    /// its own page and a link from the index while staying out of the feed and the sitemap, so
    /// nothing you would think to check showed it. Only preview callers should pass true.
    @discardableResult
    public func build(siteURL: URL, outputURL: URL? = nil, includeDrafts: Bool = false) throws -> BuildSummary {
        let store = SiteStore(siteURL: siteURL)
        let config = try store.loadConfig()
        let allPosts = try store.loadPosts()
        let published = allPosts.filter { !$0.post.draft }
        let visible = includeDrafts ? allPosts : published
        let allPages = try store.loadPages()
        let visiblePages = includeDrafts ? allPages : allPages.filter { !$0.page.draft }
        let output = outputURL ?? siteURL.appendingPathComponent("dist")

        guard output.standardizedFileURL != siteURL.standardizedFileURL else {
            throw OverprintError.io("refusing to build into the site root")
        }

        let theme = try Theme.load(siteURL: siteURL)
        let environment = Environment(loader: DictionaryLoader(templates: theme.templates))
        let renderer = MarkdownRenderer()
        let fileManager = FileManager.default

        // Recreate the output directory from scratch.
        if fileManager.fileExists(atPath: output.path) {
            try fileManager.removeItem(at: output)
        }
        try fileManager.createDirectory(at: output, withIntermediateDirectories: true)

        // Every path this build writes, relative to dist/. `static/` is checked against it below
        // so a passthrough file can never quietly replace generated output, or be replaced by it.
        var generated: Set<String> = []
        func record(_ relative: String) { generated.insert(relative) }

        // Stylesheet, plus anything else the site keeps in theme/assets/ for its CSS to reference.
        let assetsDir = output.appendingPathComponent("assets")
        try fileManager.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        try theme.styleCSS.write(to: assetsDir.appendingPathComponent("style.css"), atomically: true, encoding: .utf8)
        record("assets/style.css")
        for (relative, source) in theme.extraAssets.sorted(by: { $0.key < $1.key }) {
            let destination = assetsDir.appendingPathComponent(relative)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: source, to: destination)
            record("assets/\(relative)")
        }

        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        let site: [String: Any] = [
            "title": HTMLEscape.escape(config.title),
            "author": HTMLEscape.escape(config.author),
            "description": HTMLEscape.escape(config.description),
            "url": HTMLEscape.escape(config.url ?? ""),
        ]
        let themeTokens = ThemeCSS.tokens(config.theme ?? SiteTheme())
        // Header navigation, shared by every template. Empty means no nav is rendered.
        let nav: [[String: String]] = (config.nav ?? []).map {
            ["label": HTMLEscape.escape($0.label), "url": HTMLEscape.escape($0.url)]
        }

        func summary(_ loaded: LoadedPost) -> [String: Any] {
            let post = loaded.post
            return [
                "title": HTMLEscape.escape(post.title),
                "slug": HTMLEscape.escape(post.slug),
                "url": HTMLEscape.escape("\(post.slug).html"),
                "dateISO": DateFormat.isoString(post.date),
                "dateDisplay": DateFormat.displayString(post.date),
                "tags": HTMLEscape.escape(post.tags),
                "draft": post.draft,
                "excerpt": HTMLEscape.escape(Summary.text(for: loaded, using: renderer)),
            ]
        }

        // Post pages, and summaries for the index.
        var summaries: [[String: Any]] = []
        for loaded in visible {
            let post = loaded.post
            let pageURL = "\(post.slug).html"
            let tagLinks = post.tags.map {
                ["name": HTMLEscape.escape($0), "url": HTMLEscape.escape("tag-\(PostWriter.slugify($0)).html")]
            }

            let context: [String: Any] = [
                "site": site,
                "theme": themeTokens,
                "nav": nav,
                "year": year,
                "title": HTMLEscape.escape(post.title),
                "slug": HTMLEscape.escape(post.slug),
                "url": HTMLEscape.escape(pageURL),
                "dateISO": DateFormat.isoString(post.date),
                "dateDisplay": DateFormat.displayString(post.date),
                "tags": HTMLEscape.escape(post.tags),
                "tag_links": tagLinks,
                "draft": post.draft,
                "description": HTMLEscape.escape(Summary.text(for: loaded, using: renderer)),
                "content_html": renderer.html(loaded.body),
            ]
            let rendered = try render(environment, name: "post.html", context: context)
            try rendered.write(to: output.appendingPathComponent(pageURL), atomically: true, encoding: .utf8)
            record(pageURL)
            summaries.append(summary(loaded))
        }

        // Index.
        let indexContext: [String: Any] = [
            "site": site,
            "theme": themeTokens,
            "nav": nav,
            "year": year,
            "description": HTMLEscape.escape(config.description),
            "posts": summaries,
        ]
        let indexHTML = try render(environment, name: "index.html", context: indexContext)
        try indexHTML.write(to: output.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        record("index.html")

        // Standalone pages. These are not posts, so they never reach the index, feed, or tags.
        // A page claiming the `404` slug is the not-found page and is rendered separately below.
        for loaded in visiblePages where loaded.page.slug != Self.notFoundSlug {
            let page = loaded.page
            let context: [String: Any] = [
                "site": site,
                "theme": themeTokens,
                "nav": nav,
                "year": year,
                "title": HTMLEscape.escape(page.title),
                "slug": HTMLEscape.escape(page.slug),
                "draft": page.draft,
                "description": HTMLEscape.escape(Summary.text(for: loaded, using: renderer)),
                "content_html": renderer.html(loaded.body),
            ]
            let rendered = try render(environment, name: "page.html", context: context)
            try rendered.write(
                to: output.appendingPathComponent("\(page.slug).html"),
                atomically: true,
                encoding: .utf8
            )
            record("\(page.slug).html")
        }

        // Tag pages (published posts only), one per unique tag, in first-seen order.
        var tagOrder: [String] = []
        var tagsBySlug: [String: (name: String, posts: [LoadedPost])] = [:]
        for loaded in published {
            for tag in loaded.post.tags {
                let slug = PostWriter.slugify(tag)
                if tagsBySlug[slug] == nil {
                    tagsBySlug[slug] = (name: tag, posts: [])
                    tagOrder.append(slug)
                }
                if tagsBySlug[slug]?.posts.contains(where: { $0.sourceURL == loaded.sourceURL }) == false {
                    tagsBySlug[slug]?.posts.append(loaded)
                }
            }
        }
        for slug in tagOrder {
            guard let entry = tagsBySlug[slug] else { continue }
            let context: [String: Any] = [
                "site": site,
                "theme": themeTokens,
                "nav": nav,
                "year": year,
                "tag": HTMLEscape.escape(entry.name),
                "posts": entry.posts.map(summary),
            ]
            let rendered = try render(environment, name: "tag.html", context: context)
            try rendered.write(to: output.appendingPathComponent("tag-\(slug).html"), atomically: true, encoding: .utf8)
        record("tag-\(slug).html")
        }

        // Not-found page. Written after everything else so it wins if some post or page also
        // claimed the slug. It is deliberately absent from the index, the feed, and the sitemap:
        // it is a response to a wrong address, not a document anyone should be pointed at.
        let notFoundPage = visiblePages.first { $0.page.slug == Self.notFoundSlug }
        let notFoundContext: [String: Any] = [
            "site": site,
            "theme": themeTokens,
            "nav": nav,
            "year": year,
            "base_path": HTMLEscape.escape(Self.basePath(from: config.url)),
            "title": HTMLEscape.escape(notFoundPage?.page.title ?? "Page not found"),
            "content_html": notFoundPage.map { renderer.html($0.body) } ?? Self.defaultNotFoundHTML,
        ]
        let notFoundHTML = try render(environment, name: "404.html", context: notFoundContext)
        try notFoundHTML.write(
            to: output.appendingPathComponent("404.html"),
            atomically: true,
            encoding: .utf8
        )
        record("404.html")

        // Feed and sitemap (published posts only).
        let feed = RSSFeed.xml(config: config, posts: published, renderer: renderer)
        try feed.write(to: output.appendingPathComponent("feed.xml"), atomically: true, encoding: .utf8)
        record("feed.xml")
        let sitemap = Sitemap.xml(config: config, posts: published)
        try sitemap.write(to: output.appendingPathComponent("sitemap.xml"), atomically: true, encoding: .utf8)
        record("sitemap.xml")

        try copyStatic(from: siteURL, into: output, avoiding: generated)

        return BuildSummary(postCount: visible.count, outputURL: output)
    }

    /// A page with this slug replaces the built-in not-found copy.
    static let notFoundSlug = "404"

    static let defaultNotFoundHTML =
        "<p>That page does not exist, or it has moved. <a href=\"index.html\">Go to the front page</a>.</p>"

    /// The directory the site is published under, for the not-found page's `<base href>`.
    ///
    /// A host answers a missing path with `404.html` without redirecting, so the browser stays on
    /// something like `/notes/typo` and every relative link in the shared templates would resolve
    /// against `/notes/` instead of the site root: no stylesheet, no working navigation. A `<base>`
    /// fixes that, but `/` is only correct for a custom domain or a user page. A GitHub Pages
    /// project site lives under `/<repo>/`, so the prefix comes from the configured `url`.
    ///
    /// Returns a path with both a leading and a trailing slash, or `/` when there is nothing to go on.
    static func basePath(from url: String?) -> String {
        guard let url, !url.isEmpty,
              let path = URLComponents(string: url)?.path,
              !path.isEmpty, path != "/"
        else { return "/" }
        let leading = path.hasPrefix("/") ? path : "/" + path
        return leading.hasSuffix("/") ? leading : leading + "/"
    }

    /// Copies `static/` verbatim into `dist/`, for favicons, images, scripts, robots.txt, CNAME.
    ///
    /// A file that would land on generated output is an error rather than a silent overwrite in
    /// either direction: whichever way it resolved, one of the two files the author wrote would
    /// vanish without a word.
    private func copyStatic(from siteURL: URL, into output: URL, avoiding generated: Set<String>) throws {
        let staticDir = siteURL.appendingPathComponent(Self.staticDirName)
        let fm = FileManager.default

        for (relative, url) in Theme.regularFiles(under: staticDir).sorted(by: { $0.key < $1.key }) {
            if generated.contains(relative) {
                throw OverprintError.io(
                    "\(Self.staticDirName)/\(relative) collides with generated output. Overprint "
                    + "writes \(relative) itself, so rename or remove this file."
                )
            }
            let destination = output.appendingPathComponent(relative)
            try fm.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try fm.copyItem(at: url, to: destination)
        }
    }

    static let staticDirName = "static"

    private func render(_ environment: Environment, name: String, context: [String: Any]) throws -> String {
        do {
            return try environment.renderTemplate(name: name, context: context)
        } catch {
            throw OverprintError.templateError("\(name): \(error)")
        }
    }
}
