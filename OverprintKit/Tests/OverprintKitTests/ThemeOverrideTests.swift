import Testing
import Foundation
@testable import OverprintKit

/// A minimal site with one published post, plus whatever theme/static files a test needs.
private func makeThemedSite(
    templates: [String: String] = [:],
    assets: [String: String] = [:],
    staticFiles: [String: String] = [:]
) throws -> URL {
    let fm = FileManager.default
    let site = fm.temporaryDirectory.appendingPathComponent("op-theme-\(UUID().uuidString)")
    try fm.createDirectory(at: site.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
    try "title: Themed\nauthor: Ada\nurl: https://themed.example.com\n"
        .write(to: site.appendingPathComponent("overprint.yml"), atomically: true, encoding: .utf8)
    try """
    ---
    title: A Post
    date: 2026-07-20
    slug: a-post
    tags: [notes]
    draft: false
    ---

    Body.
    """.write(to: site.appendingPathComponent("content/posts/2026-07-20-a-post.md"),
              atomically: true, encoding: .utf8)

    func write(_ files: [String: String], under relative: String) throws {
        guard !files.isEmpty else { return }
        for (name, body) in files {
            let url = site.appendingPathComponent(relative).appendingPathComponent(name)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try body.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    try write(templates, under: "theme/templates")
    try write(assets, under: "theme/assets")
    try write(staticFiles, under: "static")
    return site
}

private func read(_ site: URL, _ relative: String) throws -> String {
    try String(contentsOf: site.appendingPathComponent("dist/\(relative)"), encoding: .utf8)
}

// MARK: Per-file fallback

@Test func overridingOneTemplateLeavesTheRestBundled() throws {
    // The point of per-file overrides: replacing the index must not oblige you to vendor base,
    // post, tag, page, nav and 404 as well.
    let site = try makeThemedSite(templates: [
        "index.html": """
        {% extends "base.html" %}
        {% block content %}<p id="mine">my index</p>{% endblock %}
        """,
    ])
    defer { try? FileManager.default.removeItem(at: site) }
    try SiteBuilder().build(siteURL: site)

    let index = try read(site, "index.html")
    #expect(index.contains("my index"))
    // Still wrapped in the bundled base, and the bundled post template still ran.
    #expect(index.contains("<!DOCTYPE html>"))
    #expect(try read(site, "a-post.html").contains("A Post"))
}

@Test func aSiteWithNoThemeDirectoryIsUnchanged() throws {
    let site = try makeThemedSite()
    defer { try? FileManager.default.removeItem(at: site) }
    try SiteBuilder().build(siteURL: site)
    #expect(try read(site, "index.html").contains("<!DOCTYPE html>"))
    #expect(SiteStore(siteURL: site).themeOverrides().isEmpty)
}

// MARK: Full override

@Test func aVendoredBaseTemplateTakesOverCompletely() throws {
    let site = try makeThemedSite(templates: [
        "base.html": """
        <!DOCTYPE html><html><head>
        {% block head_top %}{% endblock %}
        <title>{% block title %}{{ site.title }}{% endblock %}</title>
        {{ theme.rootStyle }}
        {% include "head.html" %}
        </head><body data-mine="yes">{% block content %}{% endblock %}</body></html>
        """,
        "head.html": "<link rel=\"icon\" href=\"/favicon.svg\">",
    ], assets: ["style.css": ":root { --mine: 1; }"])
    defer { try? FileManager.default.removeItem(at: site) }
    try SiteBuilder().build(siteURL: site)

    let index = try read(site, "index.html")
    #expect(index.contains("data-mine=\"yes\""))
    #expect(index.contains("favicon.svg"))
    // The bundled Google Fonts link came from base.html, which is gone now.
    #expect(!index.contains("fonts.googleapis.com"))
    #expect(try read(site, "assets/style.css") == ":root { --mine: 1; }")
    #expect(SiteStore(siteURL: site).themeOverrides() == ["assets/style.css", "base.html", "head.html"])
}

@Test func headTemplateIsInjectedWithoutVendoringBase() throws {
    // The narrow escape hatch: fonts, favicons and a pre-paint script without owning base.html.
    let site = try makeThemedSite(templates: [
        "head.html": "<script>document.documentElement.dataset.theme='dark'</script>",
    ])
    defer { try? FileManager.default.removeItem(at: site) }
    try SiteBuilder().build(siteURL: site)

    let index = try read(site, "index.html")
    #expect(index.contains("dataset.theme"))
    // Injected last in <head>, so it wins over the bundled stylesheet.
    let script = try #require(index.range(of: "dataset.theme"))
    let css = try #require(index.range(of: "assets/style.css"))
    #expect(css.lowerBound < script.lowerBound)
    #expect(index.contains("</head>"))
}

// MARK: Tokens survive an override

@Test func tokenBlockIsStillEmittedUnderAnOverride() throws {
    let site = try makeThemedSite(assets: ["style.css": "body { color: var(--accent); }"])
    defer { try? FileManager.default.removeItem(at: site) }
    try SiteBuilder().build(siteURL: site)

    // Custom CSS can consume the generated tokens, or ignore them.
    let index = try read(site, "index.html")
    #expect(index.contains("--accent"))
    #expect(index.contains(":root"))
}

// MARK: Extra assets

@Test func extraThemeAssetsAreCopiedNextToTheStylesheet() throws {
    let site = try makeThemedSite(assets: [
        "style.css": "@font-face { src: url(fonts/x.woff2); }",
        "fonts/x.woff2": "not-really-a-font",
    ])
    defer { try? FileManager.default.removeItem(at: site) }
    try SiteBuilder().build(siteURL: site)
    #expect(try read(site, "assets/fonts/x.woff2") == "not-really-a-font")
}

// MARK: Static passthrough

@Test func staticFilesAreCopiedVerbatimToTheSiteRoot() throws {
    let site = try makeThemedSite(staticFiles: [
        "CNAME": "blog.example.com",
        "robots.txt": "User-agent: *\n",
        "img/share.png": "png-bytes",
    ])
    defer { try? FileManager.default.removeItem(at: site) }
    try SiteBuilder().build(siteURL: site)
    #expect(try read(site, "CNAME") == "blog.example.com")
    #expect(try read(site, "robots.txt") == "User-agent: *\n")
    #expect(try read(site, "img/share.png") == "png-bytes")
}

@Test func aStaticFileThatWouldClobberGeneratedOutputIsAnError() throws {
    for colliding in ["index.html", "feed.xml", "sitemap.xml", "404.html", "a-post.html", "assets/style.css"] {
        let site = try makeThemedSite(staticFiles: [colliding: "mine"])
        defer { try? FileManager.default.removeItem(at: site) }
        #expect(throws: OverprintError.self) {
            try SiteBuilder().build(siteURL: site)
        }
    }
}

// MARK: Validation

@Test func aTypoedTemplateNameIsRejectedRatherThanIgnored() throws {
    let site = try makeThemedSite(templates: ["pots.html": "oops"])
    defer { try? FileManager.default.removeItem(at: site) }

    let issues = SiteStore(siteURL: site).validate()
    #expect(issues.contains { $0.description.contains("pots.html") })
    // And the build refuses too, so skipping validate does not hide it.
    #expect(throws: OverprintError.self) { try SiteBuilder().build(siteURL: site) }
}

@Test func ownPartialsAreAllowedWithAnUnderscore() throws {
    let site = try makeThemedSite(templates: [
        "_aside.html": "<aside>mine</aside>",
        "index.html": "{% extends \"base.html\" %}{% block content %}{% include \"_aside.html\" %}{% endblock %}",
    ])
    defer { try? FileManager.default.removeItem(at: site) }
    #expect(SiteStore(siteURL: site).validate().isEmpty)
    try SiteBuilder().build(siteURL: site)
    #expect(try read(site, "index.html").contains("<aside>mine</aside>"))
}

@Test func aVendoredBaseMissingItsContractIsReported() throws {
    // Dropping head_top silently breaks the 404 page's <base href>; dropping rootStyle silently
    // removes the token block. Neither shows up by looking at the index.
    let site = try makeThemedSite(templates: [
        "base.html": "<html><head><title>{% block title %}{% endblock %}</title></head><body>{% block content %}{% endblock %}</body></html>",
    ])
    defer { try? FileManager.default.removeItem(at: site) }

    let issues = SiteStore(siteURL: site).validate().map(\.description)
    #expect(issues.contains { $0.contains("head_top") })
    #expect(issues.contains { $0.contains("theme.rootStyle") })
}

@Test func the404BaseHrefSurvivesAnOverriddenBase() throws {
    let site = try makeThemedSite(templates: [
        "base.html": """
        <!DOCTYPE html><html><head>
        {% block head_top %}{% endblock %}
        <title>{% block title %}{{ site.title }}{% endblock %}</title>
        {{ theme.rootStyle }}
        {% include "head.html" %}
        </head><body>{% block content %}{% endblock %}</body></html>
        """,
    ])
    defer { try? FileManager.default.removeItem(at: site) }
    #expect(SiteStore(siteURL: site).validate().isEmpty)
    try SiteBuilder().build(siteURL: site)
    #expect(try read(site, "404.html").contains("<base href=\"/\">"))
}
