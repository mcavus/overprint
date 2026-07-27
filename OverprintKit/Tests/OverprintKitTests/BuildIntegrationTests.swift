import Testing
import Foundation
@testable import OverprintKit

@Test func buildsSyntheticSiteToTempDir() throws {
    let fm = FileManager.default
    let site = fm.temporaryDirectory.appendingPathComponent("op-site-\(UUID().uuidString)")
    let postsDir = site.appendingPathComponent("content/posts")
    try fm.createDirectory(at: postsDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: site) }

    try "title: Test Blog\nauthor: Ada\ndescription: hi\n"
        .write(to: site.appendingPathComponent("overprint.yml"), atomically: true, encoding: .utf8)

    try """
    ---
    title: First Post
    date: 2026-01-02
    slug: first
    ---

    # Hello

    World with **bold** text.
    """.write(to: postsDir.appendingPathComponent("2026-01-02-first.md"), atomically: true, encoding: .utf8)

    try """
    ---
    title: Older Post
    date: 2026-01-01
    slug: older
    ---

    Just some words.
    """.write(to: postsDir.appendingPathComponent("2026-01-01-older.md"), atomically: true, encoding: .utf8)

    let output = site.appendingPathComponent("out")
    let summary = try SiteBuilder().build(siteURL: site, outputURL: output)
    #expect(summary.postCount == 2)

    // Index lists both titles, newest first.
    let index = try String(contentsOf: output.appendingPathComponent("index.html"), encoding: .utf8)
    #expect(index.contains("First Post"))
    #expect(index.contains("Older Post"))
    #expect(index.contains("Test Blog"))
    if let first = index.range(of: "First Post"), let older = index.range(of: "Older Post") {
        #expect(first.lowerBound < older.lowerBound) // newest first
    }

    // Each post page exists with rendered (not escaped) HTML.
    let post = try String(contentsOf: output.appendingPathComponent("first.html"), encoding: .utf8)
    #expect(post.contains("<strong>bold</strong>"))
    #expect(!post.contains("&lt;strong&gt;"))
    #expect(post.contains("<h1"))

    // Stylesheet copied.
    #expect(fm.fileExists(atPath: output.appendingPathComponent("assets/style.css").path))
}

@Test func refusesToBuildIntoSiteRoot() throws {
    let fm = FileManager.default
    let site = fm.temporaryDirectory.appendingPathComponent("op-root-\(UUID().uuidString)")
    try fm.createDirectory(at: site.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
    try "title: X\n".write(to: site.appendingPathComponent("overprint.yml"), atomically: true, encoding: .utf8)
    defer { try? fm.removeItem(at: site) }

    #expect(throws: OverprintError.self) {
        _ = try SiteBuilder().build(siteURL: site, outputURL: site)
    }
}
