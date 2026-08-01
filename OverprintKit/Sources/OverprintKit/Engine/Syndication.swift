import Foundation

/// Shared URL and escaping helpers for the XML artifacts (feed, sitemap).
enum SyndicationURL {
    /// The site base with any trailing slash removed; empty when no `url` is configured.
    static func base(_ url: String?) -> String {
        guard var value = url?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return "" }
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    /// An absolute URL for `path` under `base`, or just `path` when there is no base.
    static func absolute(_ base: String, _ path: String) -> String {
        base.isEmpty ? path : "\(base)/\(path)"
    }

    static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

/// Builds an RSS 2.0 feed (`feed.xml`) from published posts. Absolute links use the site's
/// configured `url`; with no url it falls back to relative page names.
enum RSSFeed {
    static func xml(config: SiteConfig, posts: [LoadedPost], renderer: MarkdownRenderer) -> String {
        let base = SyndicationURL.base(config.url)
        let escape = SyndicationURL.escape

        var items: [String] = []
        for loaded in posts {
            let post = loaded.post
            let link = SyndicationURL.absolute(base, "\(post.slug).html")
            let isPermaLink = base.isEmpty ? "false" : "true"
            items.append("""
                <item>
                  <title>\(escape(post.title))</title>
                  <link>\(escape(link))</link>
                  <guid isPermaLink="\(isPermaLink)">\(escape(link))</guid>
                  <pubDate>\(DateFormat.rfc822String(post.date))</pubDate>
                  <description>\(escape(Summary.text(for: loaded, using: renderer)))</description>
                </item>
            """)
        }

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
          <channel>
            <title>\(escape(config.title))</title>
            <link>\(escape(base))</link>
            <atom:link href="\(escape(SyndicationURL.absolute(base, "feed.xml")))" rel="self" type="application/rss+xml" />
            <description>\(escape(config.description))</description>
        \(items.joined(separator: "\n"))
          </channel>
        </rss>
        """
    }
}

/// Builds a sitemap (`sitemap.xml`): the index plus each published post, newest date as
/// `lastmod`.
enum Sitemap {
    static func xml(config: SiteConfig, posts: [LoadedPost]) -> String {
        let base = SyndicationURL.base(config.url)
        let escape = SyndicationURL.escape

        var entries: [String] = []
        let indexLoc = base.isEmpty ? "index.html" : "\(base)/"
        entries.append(urlEntry(loc: escape(indexLoc), lastmod: posts.first.map { DateFormat.isoString($0.post.date) }))
        for loaded in posts {
            let loc = SyndicationURL.absolute(base, "\(loaded.post.slug).html")
            entries.append(urlEntry(loc: escape(loc), lastmod: DateFormat.isoString(loaded.post.date)))
        }

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        \(entries.joined(separator: "\n"))
        </urlset>
        """
    }

    private static func urlEntry(loc: String, lastmod: String?) -> String {
        if let lastmod {
            return "  <url><loc>\(loc)</loc><lastmod>\(lastmod)</lastmod></url>"
        }
        return "  <url><loc>\(loc)</loc></url>"
    }
}
