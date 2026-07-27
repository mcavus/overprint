import Testing
import Foundation
@testable import OverprintKit

/// Builds a temp site with one post, one page, and an optional nav block.
private func makePageSite(nav: String = "", draftPage: Bool = false) throws -> URL {
    let fm = FileManager.default
    let site = fm.temporaryDirectory.appendingPathComponent("op-page-\(UUID().uuidString)")
    try fm.createDirectory(at: site.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
    try fm.createDirectory(at: site.appendingPathComponent("content/pages"), withIntermediateDirectories: true)

    try "title: Page Site\nauthor: Ada\n\(nav)"
        .write(to: site.appendingPathComponent("overprint.yml"), atomically: true, encoding: .utf8)
    try """
    ---
    title: A Post
    date: 2026-07-20
    slug: a-post
    tags: [notes]
    ---

    Post body.
    """.write(to: site.appendingPathComponent("content/posts/2026-07-20-a-post.md"), atomically: true, encoding: .utf8)
    try """
    ---
    title: About
    \(draftPage ? "draft: true" : "")
    ---

    About body.
    """.write(to: site.appendingPathComponent("content/pages/about.md"), atomically: true, encoding: .utf8)
    return site
}

@Test func pageRendersToFlatHTML() throws {
    let fm = FileManager.default
    let site = try makePageSite()
    defer { try? fm.removeItem(at: site) }
    let out = site.appendingPathComponent("out")
    try SiteBuilder().build(siteURL: site, outputURL: out)

    let about = try String(contentsOf: out.appendingPathComponent("about.html"), encoding: .utf8)
    #expect(about.contains("About"))
    #expect(about.contains("About body."))
}

@Test func pageStaysOutOfIndexFeedAndSitemap() throws {
    let fm = FileManager.default
    let site = try makePageSite()
    defer { try? fm.removeItem(at: site) }
    let out = site.appendingPathComponent("out")
    try SiteBuilder().build(siteURL: site, outputURL: out)

    // A page is not a post: it must not appear in the post list, the feed, or the sitemap.
    let index = try String(contentsOf: out.appendingPathComponent("index.html"), encoding: .utf8)
    #expect(!index.contains("about.html"))
    let feed = try String(contentsOf: out.appendingPathComponent("feed.xml"), encoding: .utf8)
    #expect(!feed.contains("about"))
    let sitemap = try String(contentsOf: out.appendingPathComponent("sitemap.xml"), encoding: .utf8)
    #expect(!sitemap.contains("about"))
}

@Test func draftPageIsExcludedFromDeployBuild() throws {
    let fm = FileManager.default
    let site = try makePageSite(draftPage: true)
    defer { try? fm.removeItem(at: site) }
    let out = site.appendingPathComponent("out")

    try SiteBuilder().build(siteURL: site, outputURL: out, includeDrafts: true)
    #expect(fm.fileExists(atPath: out.appendingPathComponent("about.html").path))

    try SiteBuilder().build(siteURL: site, outputURL: out, includeDrafts: false)
    #expect(!fm.fileExists(atPath: out.appendingPathComponent("about.html").path))
}

@Test func navRendersAsLinksOnEveryTemplate() throws {
    let fm = FileManager.default
    let navBlock = """
    nav:
      - { label: Writing, url: index.html }
      - { label: About, url: about.html }

    """
    let site = try makePageSite(nav: navBlock)
    defer { try? fm.removeItem(at: site) }
    let out = site.appendingPathComponent("out")
    try SiteBuilder().build(siteURL: site, outputURL: out)

    for file in ["index.html", "a-post.html", "about.html", "tag-notes.html"] {
        let html = try String(contentsOf: out.appendingPathComponent(file), encoding: .utf8)
        #expect(html.contains("<a href=\"about.html\">About</a>"), "nav missing in \(file)")
        #expect(html.contains("<a href=\"index.html\">Writing</a>"), "nav missing in \(file)")
    }
}

@Test func noNavRendersWhenNotConfigured() throws {
    let fm = FileManager.default
    let site = try makePageSite() // no nav block
    defer { try? fm.removeItem(at: site) }
    let out = site.appendingPathComponent("out")
    try SiteBuilder().build(siteURL: site, outputURL: out)

    let index = try String(contentsOf: out.appendingPathComponent("index.html"), encoding: .utf8)
    // The old placeholder spans are gone, and no empty nav is emitted.
    #expect(!index.contains("site-nav"))
    #expect(!index.contains("<span>Writing</span>"))
}

@Test func navRoundTripsThroughConfig() throws {
    let fm = FileManager.default
    let url = fm.temporaryDirectory.appendingPathComponent("cfg-\(UUID().uuidString).yml")
    defer { try? fm.removeItem(at: url) }

    let config = SiteConfig(title: "X", nav: [NavItem(label: "About", url: "about.html")])
    try config.save(to: url)
    let loaded = try SiteConfig.load(from: url)
    #expect(loaded.nav?.count == 1)
    #expect(loaded.nav?.first?.label == "About")
    #expect(loaded.nav?.first?.url == "about.html")
}

@Test func validateCatchesDuplicateSlugsAcrossPostsAndPages() throws {
    let fm = FileManager.default
    let site = try makePageSite()
    defer { try? fm.removeItem(at: site) }

    // Clean site validates.
    #expect(SiteStore(siteURL: site).validate().isEmpty)

    // A second post claiming the same slug would silently overwrite the first in dist/.
    try """
    ---
    title: Duplicate
    date: 2026-07-21
    slug: a-post
    ---

    Body.
    """.write(to: site.appendingPathComponent("content/posts/2026-07-21-duplicate.md"), atomically: true, encoding: .utf8)
    #expect(!SiteStore(siteURL: site).validate().isEmpty)
}

@Test func validateChecksPagesNotJustPosts() throws {
    let fm = FileManager.default
    let site = try makePageSite()
    defer { try? fm.removeItem(at: site) }

    // A page missing its required title must be reported, not silently ignored.
    try "---\nslug: broken\n---\n\nNo title."
        .write(to: site.appendingPathComponent("content/pages/broken.md"), atomically: true, encoding: .utf8)
    let errors = SiteStore(siteURL: site).validate()
    #expect(!errors.isEmpty)
}

@Test func pageWithoutTitleThrows() throws {
    #expect(throws: OverprintError.self) {
        _ = try FrontmatterParser().parsePage("---\nslug: x\n---\n\nBody.", filename: "x.md")
    }
}
