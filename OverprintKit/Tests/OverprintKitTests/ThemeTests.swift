import Testing
import Foundation
@testable import OverprintKit

@Test func themeRoundTripsThroughConfig() throws {
    let fm = FileManager.default
    let url = fm.temporaryDirectory.appendingPathComponent("cfg-\(UUID().uuidString).yml")
    defer { try? fm.removeItem(at: url) }

    let config = SiteConfig(
        title: "Blog",
        author: "Ada",
        description: "d",
        theme: SiteTheme(mode: .dark, accent: "#FF6A00", font: .sans)
    )
    try config.save(to: url)

    let loaded = try SiteConfig.load(from: url)
    #expect(loaded.theme?.mode == .dark)
    #expect(loaded.theme?.accent == "#FF6A00")
    #expect(loaded.theme?.font == .sans)
    #expect(loaded == config)
}

@Test func configWithoutThemeDecodesNil() throws {
    let fm = FileManager.default
    let url = fm.temporaryDirectory.appendingPathComponent("cfg-\(UUID().uuidString).yml")
    try "title: Only Title\n".write(to: url, atomically: true, encoding: .utf8)
    defer { try? fm.removeItem(at: url) }

    let loaded = try SiteConfig.load(from: url)
    #expect(loaded.theme == nil)
}

@Test func backgroundOverridesPaperInDist() throws {
    let fm = FileManager.default
    let site = fm.temporaryDirectory.appendingPathComponent("op-bg-\(UUID().uuidString)")
    let postsDir = site.appendingPathComponent("content/posts")
    try fm.createDirectory(at: postsDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: site) }

    let config = SiteConfig(title: "Cream", theme: SiteTheme(mode: .light, accent: "#3355FF", font: .serif, background: "#F5EBDC"))
    try config.save(to: site.appendingPathComponent("overprint.yml"))
    try """
    ---
    title: A Post
    date: 2026-01-02
    slug: a-post
    ---

    Body.
    """.write(to: postsDir.appendingPathComponent("2026-01-02-a-post.md"), atomically: true, encoding: .utf8)

    let output = site.appendingPathComponent("out")
    try SiteBuilder().build(siteURL: site, outputURL: output)

    let index = try String(contentsOf: output.appendingPathComponent("index.html"), encoding: .utf8)
    #expect(index.contains("--paper: #F5EBDC"))
    #expect(index.contains("--accent: #3355FF"))
    // Still light mode, so no dark override.
    #expect(!index.contains("--paper: #14141b"))
}

@Test func backgroundRoundTripsThroughConfig() throws {
    let fm = FileManager.default
    let url = fm.temporaryDirectory.appendingPathComponent("cfg-\(UUID().uuidString).yml")
    defer { try? fm.removeItem(at: url) }

    let config = SiteConfig(title: "Blog", theme: SiteTheme(background: "#F5EBDC"))
    try config.save(to: url)
    let loaded = try SiteConfig.load(from: url)
    #expect(loaded.theme?.background == "#F5EBDC")
}

@Test func invalidBackgroundIsIgnored() throws {
    let fm = FileManager.default
    let site = fm.temporaryDirectory.appendingPathComponent("op-badbg-\(UUID().uuidString)")
    let postsDir = site.appendingPathComponent("content/posts")
    try fm.createDirectory(at: postsDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: site) }

    let config = SiteConfig(title: "X", theme: SiteTheme(background: "creme"))
    try config.save(to: site.appendingPathComponent("overprint.yml"))
    try """
    ---
    title: P
    date: 2026-01-02
    slug: p
    ---

    Body.
    """.write(to: postsDir.appendingPathComponent("2026-01-02-p.md"), atomically: true, encoding: .utf8)

    let output = site.appendingPathComponent("out")
    try SiteBuilder().build(siteURL: site, outputURL: output)
    let index = try String(contentsOf: output.appendingPathComponent("index.html"), encoding: .utf8)
    // "creme" isn't a hex, so no --paper override is emitted.
    #expect(!index.contains("--paper:"))
}

@Test func themeCSSSafeHexRejectsGarbage() {
    #expect(ThemeCSS.safeHex("#0A7AFF") == "#0A7AFF")
    #expect(ThemeCSS.safeHex("#fff") == "#fff")
    #expect(ThemeCSS.safeHex("red") == "#0A7AFF")
    #expect(ThemeCSS.safeHex("#12345") == "#0A7AFF")
    #expect(ThemeCSS.safeHex("#zzzzzz") == "#0A7AFF")
}

@Test func darkThemeBuildsDarkPaperOverrideIntoIndex() throws {
    let fm = FileManager.default
    let site = fm.temporaryDirectory.appendingPathComponent("op-theme-\(UUID().uuidString)")
    let postsDir = site.appendingPathComponent("content/posts")
    try fm.createDirectory(at: postsDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: site) }

    let config = SiteConfig(title: "Dark Blog", theme: SiteTheme(mode: .dark, accent: "#FF6A00", font: .serif))
    try config.save(to: site.appendingPathComponent("overprint.yml"))

    try """
    ---
    title: A Post
    date: 2026-01-02
    slug: a-post
    ---

    Body.
    """.write(to: postsDir.appendingPathComponent("2026-01-02-a-post.md"), atomically: true, encoding: .utf8)

    let output = site.appendingPathComponent("out")
    try SiteBuilder().build(siteURL: site, outputURL: output)

    let index = try String(contentsOf: output.appendingPathComponent("index.html"), encoding: .utf8)
    #expect(index.contains("--paper: #14141b"))
    #expect(index.contains("--accent: #FF6A00"))

    let post = try String(contentsOf: output.appendingPathComponent("a-post.html"), encoding: .utf8)
    #expect(post.contains("--paper: #14141b"))
}

@Test func lightThemeOmitsDarkPaperOverride() throws {
    let fm = FileManager.default
    let site = fm.temporaryDirectory.appendingPathComponent("op-light-\(UUID().uuidString)")
    let postsDir = site.appendingPathComponent("content/posts")
    try fm.createDirectory(at: postsDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: site) }

    // No theme block at all: defaults to light.
    try "title: Light Blog\n".write(to: site.appendingPathComponent("overprint.yml"), atomically: true, encoding: .utf8)
    try """
    ---
    title: A Post
    date: 2026-01-02
    slug: a-post
    ---

    Body.
    """.write(to: postsDir.appendingPathComponent("2026-01-02-a-post.md"), atomically: true, encoding: .utf8)

    let output = site.appendingPathComponent("out")
    try SiteBuilder().build(siteURL: site, outputURL: output)

    let index = try String(contentsOf: output.appendingPathComponent("index.html"), encoding: .utf8)
    #expect(!index.contains("--paper: #14141b"))
    #expect(index.contains("--accent: #0A7AFF"))
}

@Test func scaffolderCreatesValidEmptySite() throws {
    let fm = FileManager.default
    let site = fm.temporaryDirectory.appendingPathComponent("op-scaffold-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: site) }

    try SiteScaffolder().scaffold(at: site, title: "Fresh Site")

    var isDir: ObjCBool = false
    #expect(fm.fileExists(atPath: site.appendingPathComponent("content/posts").path, isDirectory: &isDir))
    #expect(isDir.boolValue)

    let config = try SiteConfig.load(from: site.appendingPathComponent("overprint.yml"))
    #expect(config.title == "Fresh Site")
    #expect(config.theme != nil)

    // The contract document ships with every new site.
    let agents = try String(contentsOf: site.appendingPathComponent("AGENTS.md"), encoding: .utf8)
    #expect(agents.contains("frozen"))
    #expect(agents.contains("content/posts/YYYY-MM-DD-slug.md"))
    #expect(agents.contains("draft"))

    // A scaffolded (post-less) site still builds.
    let output = site.appendingPathComponent("out")
    let summary = try SiteBuilder().build(siteURL: site, outputURL: output)
    #expect(summary.postCount == 0)
    #expect(fm.fileExists(atPath: output.appendingPathComponent("index.html").path))
}

@Test func postWriterHonorsBodyTagsAndDraft() throws {
    let fm = FileManager.default
    let site = fm.temporaryDirectory.appendingPathComponent("op-writer-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: site) }

    let url = try PostWriter().createPost(
        in: site,
        title: "Hello World",
        date: DateFormat.parse("2026-03-04")!,
        body: "Custom body text.",
        tags: ["swift", "macos"],
        draft: false
    )

    #expect(url.lastPathComponent == "2026-03-04-hello-world.md")
    let content = try String(contentsOf: url, encoding: .utf8)
    #expect(content.contains("tags: [\"swift\", \"macos\"]"))
    #expect(content.contains("draft: false"))
    #expect(content.contains("Custom body text."))
}
