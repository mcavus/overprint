import Testing
import Foundation
@testable import OverprintKit

/// Creates a temp site with two published posts (Alpha: swift+macos, Beta: swift) and one draft
/// (Draft One: swift+secret). Returns the site URL; caller removes it.
private func makeSite(url: String? = nil) throws -> URL {
    let fm = FileManager.default
    let site = fm.temporaryDirectory.appendingPathComponent("op-s7-\(UUID().uuidString)")
    let postsDir = site.appendingPathComponent("content/posts")
    try fm.createDirectory(at: postsDir, withIntermediateDirectories: true)

    let urlLine = url.map { "url: \($0)\n" } ?? ""
    try "title: Test Blog\nauthor: Ada\ndescription: hi\n\(urlLine)"
        .write(to: site.appendingPathComponent("overprint.yml"), atomically: true, encoding: .utf8)

    try """
    ---
    title: Alpha
    date: 2026-03-03
    slug: alpha
    tags: [swift, macos]
    ---

    Alpha body.
    """.write(to: postsDir.appendingPathComponent("2026-03-03-alpha.md"), atomically: true, encoding: .utf8)

    try """
    ---
    title: Beta
    date: 2026-02-02
    slug: beta
    tags: [swift]
    ---

    Beta body.
    """.write(to: postsDir.appendingPathComponent("2026-02-02-beta.md"), atomically: true, encoding: .utf8)

    try """
    ---
    title: Draft One
    date: 2026-04-04
    slug: draft-one
    tags: [swift, secret]
    draft: true
    ---

    Draft body.
    """.write(to: postsDir.appendingPathComponent("2026-04-04-draft-one.md"), atomically: true, encoding: .utf8)

    return site
}

@Test func draftIncludedByDefault() throws {
    let fm = FileManager.default
    let site = try makeSite()
    defer { try? fm.removeItem(at: site) }
    let out = site.appendingPathComponent("out")
    let summary = try SiteBuilder().build(siteURL: site, outputURL: out)

    #expect(summary.postCount == 3)
    #expect(fm.fileExists(atPath: out.appendingPathComponent("draft-one.html").path))
    let index = try String(contentsOf: out.appendingPathComponent("index.html"), encoding: .utf8)
    #expect(index.contains("Draft One"))
    #expect(index.contains("draft-tag")) // the "Draft" marker
}

@Test func draftExcludedWhenNotIncluded() throws {
    let fm = FileManager.default
    let site = try makeSite()
    defer { try? fm.removeItem(at: site) }
    let out = site.appendingPathComponent("out")
    let summary = try SiteBuilder().build(siteURL: site, outputURL: out, includeDrafts: false)

    #expect(summary.postCount == 2)
    #expect(!fm.fileExists(atPath: out.appendingPathComponent("draft-one.html").path))
    let index = try String(contentsOf: out.appendingPathComponent("index.html"), encoding: .utf8)
    #expect(index.contains("Alpha"))
    #expect(!index.contains("Draft One"))
}

@Test func feedExcludesDraftsAndListsPublished() throws {
    let fm = FileManager.default
    let site = try makeSite()
    defer { try? fm.removeItem(at: site) }
    let out = site.appendingPathComponent("out")
    // Even with includeDrafts true, the feed excludes drafts.
    try SiteBuilder().build(siteURL: site, outputURL: out, includeDrafts: true)

    let feed = try String(contentsOf: out.appendingPathComponent("feed.xml"), encoding: .utf8)
    #expect(feed.contains("<rss version=\"2.0\">"))
    #expect(feed.contains("<title>Test Blog</title>"))
    #expect(feed.contains("<title>Alpha</title>"))
    #expect(feed.contains("<title>Beta</title>"))
    #expect(!feed.contains("Draft One"))
}

@Test func feedUsesAbsoluteLinksWhenURLSet() throws {
    let fm = FileManager.default
    let site = try makeSite(url: "https://example.com/")
    defer { try? fm.removeItem(at: site) }
    let out = site.appendingPathComponent("out")
    try SiteBuilder().build(siteURL: site, outputURL: out)

    let feed = try String(contentsOf: out.appendingPathComponent("feed.xml"), encoding: .utf8)
    #expect(feed.contains("<link>https://example.com/alpha.html</link>"))
    #expect(feed.contains("isPermaLink=\"true\""))
}

@Test func feedWorksWithoutURL() throws {
    let fm = FileManager.default
    let site = try makeSite() // no url
    defer { try? fm.removeItem(at: site) }
    let out = site.appendingPathComponent("out")
    try SiteBuilder().build(siteURL: site, outputURL: out)

    let feed = try String(contentsOf: out.appendingPathComponent("feed.xml"), encoding: .utf8)
    #expect(feed.contains("<link>alpha.html</link>"))
    #expect(feed.contains("isPermaLink=\"false\""))
}

@Test func sitemapListsPublishedPosts() throws {
    let fm = FileManager.default
    let site = try makeSite(url: "https://example.com")
    defer { try? fm.removeItem(at: site) }
    let out = site.appendingPathComponent("out")
    try SiteBuilder().build(siteURL: site, outputURL: out)

    let sitemap = try String(contentsOf: out.appendingPathComponent("sitemap.xml"), encoding: .utf8)
    #expect(sitemap.contains("<urlset"))
    #expect(sitemap.contains("<loc>https://example.com/alpha.html</loc>"))
    #expect(sitemap.contains("<loc>https://example.com/beta.html</loc>"))
    #expect(sitemap.contains("<lastmod>2026-03-03</lastmod>"))
    #expect(!sitemap.contains("draft-one"))
}

@Test func tagPagesGeneratedAndExcludeDrafts() throws {
    let fm = FileManager.default
    let site = try makeSite()
    defer { try? fm.removeItem(at: site) }
    let out = site.appendingPathComponent("out")
    try SiteBuilder().build(siteURL: site, outputURL: out)

    // swift and macos come from published posts; secret is only on the draft.
    #expect(fm.fileExists(atPath: out.appendingPathComponent("tag-swift.html").path))
    #expect(fm.fileExists(atPath: out.appendingPathComponent("tag-macos.html").path))
    #expect(!fm.fileExists(atPath: out.appendingPathComponent("tag-secret.html").path))

    let swiftPage = try String(contentsOf: out.appendingPathComponent("tag-swift.html"), encoding: .utf8)
    #expect(swiftPage.contains("Alpha"))
    #expect(swiftPage.contains("Beta"))
    #expect(!swiftPage.contains("Draft One"))

    let macosPage = try String(contentsOf: out.appendingPathComponent("tag-macos.html"), encoding: .utf8)
    #expect(macosPage.contains("Alpha"))
    #expect(!macosPage.contains("Beta"))
}

@Test func postPageLinksTags() throws {
    let fm = FileManager.default
    let site = try makeSite()
    defer { try? fm.removeItem(at: site) }
    let out = site.appendingPathComponent("out")
    try SiteBuilder().build(siteURL: site, outputURL: out)

    let alpha = try String(contentsOf: out.appendingPathComponent("alpha.html"), encoding: .utf8)
    #expect(alpha.contains("href=\"tag-swift.html\""))
    #expect(alpha.contains("href=\"tag-macos.html\""))
}
