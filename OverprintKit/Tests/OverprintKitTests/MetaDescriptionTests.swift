import Testing
import Foundation
@testable import OverprintKit

/// Builds a temp site with a single post, so the meta description can be read off the built page.
private func makeDescriptionSite(
    config: String = "title: A Site\ndescription: What the site is about.\n",
    postFrontmatter: String,
    body: String
) throws -> URL {
    let fm = FileManager.default
    let site = fm.temporaryDirectory.appendingPathComponent("op-desc-\(UUID().uuidString)")
    try fm.createDirectory(at: site.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
    try config.write(to: site.appendingPathComponent("overprint.yml"), atomically: true, encoding: .utf8)
    try "---\n\(postFrontmatter)\n---\n\n\(body)"
        .write(to: site.appendingPathComponent("content/posts/2026-01-01-a.md"), atomically: true, encoding: .utf8)
    return site
}

private let basePost = """
title: A post
date: 2026-01-01
tags: []
slug: a
draft: false
"""

/// One rule feeds the index card, the feed entry, and the meta tag, so they cannot disagree.
@Test func postPageCarriesAMetaDescription() throws {
    let fm = FileManager.default
    let site = try makeDescriptionSite(postFrontmatter: basePost, body: "The opening paragraph.")
    defer { try? fm.removeItem(at: site) }
    let out = site.appendingPathComponent("out")
    try SiteBuilder().build(siteURL: site, outputURL: out)

    let html = try String(contentsOf: out.appendingPathComponent("a.html"), encoding: .utf8)
    #expect(html.contains("<meta name=\"description\" content=\"The opening paragraph.\">"))
    #expect(html.contains("<meta property=\"og:description\" content=\"The opening paragraph.\">"))
}

@Test func frontmatterDescriptionOverridesTheFirstParagraph() throws {
    let fm = FileManager.default
    let site = try makeDescriptionSite(
        postFrontmatter: basePost + "\ndescription: A sharper line, written for search results.",
        body: "The opening paragraph.")
    defer { try? fm.removeItem(at: site) }
    let out = site.appendingPathComponent("out")
    try SiteBuilder().build(siteURL: site, outputURL: out)

    let html = try String(contentsOf: out.appendingPathComponent("a.html"), encoding: .utf8)
    #expect(html.contains("content=\"A sharper line, written for search results.\""))
    // The body still renders; it is the meta tag that must not fall back to it.
    #expect(!html.contains("content=\"The opening paragraph.\""))
    // The override feeds the listing and the feed too, not only the meta tag.
    let index = try String(contentsOf: out.appendingPathComponent("index.html"), encoding: .utf8)
    #expect(index.contains("A sharper line, written for search results."))
    let feed = try String(contentsOf: out.appendingPathComponent("feed.xml"), encoding: .utf8)
    #expect(feed.contains("A sharper line, written for search results."))
}

/// A break is a childless leaf, so a walker that only recurses renders it as nothing and runs the
/// words on either side together.
@Test func summaryKeepsWordsApartAcrossALineBreak() {
    let text = MarkdownRenderer().excerpt("First line of the paragraph\nsecond line of the same.")
    #expect(text.contains("paragraph second"))
    #expect(!text.contains("paragraphsecond"))
}

/// An empty value would emit `content=""`, which is worse than omitting the tag.
@Test func noDescriptionMeansNoMetaTag() throws {
    let fm = FileManager.default
    let site = try makeDescriptionSite(config: "title: A Site\n",
                                       postFrontmatter: basePost, body: "")
    defer { try? fm.removeItem(at: site) }
    let out = site.appendingPathComponent("out")
    try SiteBuilder().build(siteURL: site, outputURL: out)

    let index = try String(contentsOf: out.appendingPathComponent("index.html"), encoding: .utf8)
    #expect(!index.contains("name=\"description\""))
}

/// The description becomes an attribute value, so a quote in it would close the attribute.
@Test func aDescriptionCannotBreakOutOfTheMetaTag() throws {
    let fm = FileManager.default
    let site = try makeDescriptionSite(
        postFrontmatter: basePost + "\ndescription: 'a\" onload=\"alert(1)'",
        body: "Body.")
    defer { try? fm.removeItem(at: site) }
    let out = site.appendingPathComponent("out")
    try SiteBuilder().build(siteURL: site, outputURL: out)

    let html = try String(contentsOf: out.appendingPathComponent("a.html"), encoding: .utf8)
    #expect(html.contains("&quot; onload=&quot;alert(1)"))
    #expect(!html.contains("onload=\"alert"))
}

/// A wrong type is ignored rather than reported, matching how `tags` and `draft` behave.
@Test func aWrongTypedDescriptionIsIgnored() throws {
    let raw = "---\n\(basePost)\ndescription: [not, a, string]\n---\n\nBody."
    let (post, _) = try FrontmatterParser().parse(raw, filename: "2026-01-01-a.md")
    #expect(post.description == nil)
}

/// A crawler stores the attribute verbatim, so a wrapped YAML scalar must not put a newline in it.
@Test func aWrappedDescriptionIsCollapsedToOneLine() throws {
    let raw = "---\n\(basePost)\ndescription: >\n  one two\n  three four\n---\n\nBody."
    let (post, _) = try FrontmatterParser().parse(raw, filename: "2026-01-01-a.md")
    let loaded = LoadedPost(post: post, body: "Body.", sourceURL: URL(fileURLWithPath: "/x.md"))
    let summary = Summary.text(for: loaded, using: MarkdownRenderer())
    #expect(!summary.contains("\n"))
    #expect(summary == "one two three four")
}

/// The index is the most-shared address, so it carries the site's own description.
@Test func indexCarriesTheSiteDescription() throws {
    let fm = FileManager.default
    let site = try makeDescriptionSite(postFrontmatter: basePost, body: "Body.")
    defer { try? fm.removeItem(at: site) }
    let out = site.appendingPathComponent("out")
    try SiteBuilder().build(siteURL: site, outputURL: out)

    let index = try String(contentsOf: out.appendingPathComponent("index.html"), encoding: .utf8)
    #expect(index.contains("<meta name=\"description\" content=\"What the site is about.\">"))
}
