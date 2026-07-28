import Testing
import Foundation
@testable import OverprintKit

/// Builds a temp site with one post, an optional `url:` in the config, and an optional page
/// claiming the `404` slug.
private func makeNotFoundSite(url: String? = nil, override: String? = nil) throws -> URL {
    let fm = FileManager.default
    let site = fm.temporaryDirectory.appendingPathComponent("op-404-\(UUID().uuidString)")
    try fm.createDirectory(at: site.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
    try fm.createDirectory(at: site.appendingPathComponent("content/pages"), withIntermediateDirectories: true)

    let urlLine = url.map { "url: \($0)\n" } ?? ""
    try "title: Not Found Site\nauthor: Ada\n\(urlLine)"
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

    if let override {
        try override.write(
            to: site.appendingPathComponent("content/pages/404.md"),
            atomically: true,
            encoding: .utf8
        )
    }
    return site
}

@Test func buildWritesANotFoundPage() throws {
    let site = try makeNotFoundSite()
    defer { try? FileManager.default.removeItem(at: site) }
    try SiteBuilder().build(siteURL: site)

    let html = try String(contentsOf: site.appendingPathComponent("dist/404.html"), encoding: .utf8)
    #expect(html.contains("Page not found"))
    #expect(html.contains("does not exist"))
    // It must look like the rest of the site, not a bare error page.
    #expect(html.contains("assets/style.css"))
    #expect(html.contains("Not Found Site"))
}

@Test func notFoundPageCarriesABaseSoRelativeLinksSurvive() throws {
    // Served at /notes/typo, a relative "assets/style.css" would resolve to /notes/assets/style.css.
    let site = try makeNotFoundSite(url: "https://blog.example.com")
    defer { try? FileManager.default.removeItem(at: site) }
    try SiteBuilder().build(siteURL: site)

    let html = try String(contentsOf: site.appendingPathComponent("dist/404.html"), encoding: .utf8)
    #expect(html.contains("<base href=\"/\">"))
    // The base has to precede the stylesheet, or it does not apply to it.
    let baseIndex = try #require(html.range(of: "<base href="))
    let cssIndex = try #require(html.range(of: "assets/style.css"))
    #expect(baseIndex.lowerBound < cssIndex.lowerBound)

    // No other page gets one: they are only ever served from their own address.
    let index = try String(contentsOf: site.appendingPathComponent("dist/index.html"), encoding: .utf8)
    #expect(!index.contains("<base href="))
}

@Test func basePathFollowsAProjectSiteSubdirectory() {
    #expect(SiteBuilder.basePath(from: nil) == "/")
    #expect(SiteBuilder.basePath(from: "") == "/")
    #expect(SiteBuilder.basePath(from: "https://blog.example.com") == "/")
    #expect(SiteBuilder.basePath(from: "https://blog.example.com/") == "/")
    // A GitHub Pages project site is served under /<repo>/, where "/" would be wrong.
    #expect(SiteBuilder.basePath(from: "https://ada.github.io/notes") == "/notes/")
    #expect(SiteBuilder.basePath(from: "https://ada.github.io/notes/") == "/notes/")
    #expect(SiteBuilder.basePath(from: "https://ada.github.io/a/b") == "/a/b/")
}

@Test func aPageClaimingTheSlugReplacesTheDefaultCopy() throws {
    let site = try makeNotFoundSite(override: """
    ---
    title: Nothing here
    ---

    This one got away. Try the [front page](index.html).
    """)
    defer { try? FileManager.default.removeItem(at: site) }
    try SiteBuilder().build(siteURL: site)

    let html = try String(contentsOf: site.appendingPathComponent("dist/404.html"), encoding: .utf8)
    #expect(html.contains("Nothing here"))
    #expect(html.contains("This one got away"))
    #expect(!html.contains("does not exist"))
    // Still the not-found page, so it still needs the base.
    #expect(html.contains("<base href="))
}

@Test func notFoundPageStaysOutOfTheFeedAndSitemap() throws {
    let site = try makeNotFoundSite(url: "https://blog.example.com", override: """
    ---
    title: Nothing here
    ---

    Body.
    """)
    defer { try? FileManager.default.removeItem(at: site) }
    try SiteBuilder().build(siteURL: site)

    let feed = try String(contentsOf: site.appendingPathComponent("dist/feed.xml"), encoding: .utf8)
    let sitemap = try String(contentsOf: site.appendingPathComponent("dist/sitemap.xml"), encoding: .utf8)
    #expect(!feed.contains("404"))
    #expect(!sitemap.contains("404"))
    #expect(!feed.contains("Nothing here"))
}

@Test func theOverridePageIsNotAlsoEmittedAsAnOrdinaryPage() throws {
    let site = try makeNotFoundSite(override: """
    ---
    title: Nothing here
    ---

    Body.
    """)
    defer { try? FileManager.default.removeItem(at: site) }
    try SiteBuilder().build(siteURL: site)

    // It renders once, as 404.html, through the not-found template.
    let html = try String(contentsOf: site.appendingPathComponent("dist/404.html"), encoding: .utf8)
    #expect(html.contains("<base href="))
    #expect(html.contains("Nothing here"))
}
