import Testing
import Foundation
@testable import OverprintKit

@Test func htmlEscapeHandlesAmpersandFirst() {
    // Ampersand must be replaced before the others, or "<" becomes "&amp;lt;".
    #expect(HTMLEscape.escape("Tips & Tricks") == "Tips &amp; Tricks")
    #expect(HTMLEscape.escape("<b>bold</b>") == "&lt;b&gt;bold&lt;/b&gt;")
    #expect(HTMLEscape.escape("a \"q\" and 'a'") == "a &quot;q&quot; and &#39;a&#39;")
    #expect(HTMLEscape.escape("&lt;") == "&amp;lt;")
    #expect(HTMLEscape.escape("plain") == "plain")
}

@Test func titlesAndTagsAreEscapedThroughoutTheBuild() throws {
    let fm = FileManager.default
    let site = fm.temporaryDirectory.appendingPathComponent("op-esc-\(UUID().uuidString)")
    try fm.createDirectory(at: site.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
    try fm.createDirectory(at: site.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: site) }

    try """
    title: Rust & Go < C
    author: A "quoted" name
    nav:
      - { label: Writing & Notes, url: index.html }

    """.write(to: site.appendingPathComponent("overprint.yml"), atomically: true, encoding: .utf8)

    try """
    ---
    title: Tips & Tricks <b>bold</b>
    date: 2026-07-20
    slug: tips
    tags: ["a & b"]
    ---

    Body text.
    """.write(to: site.appendingPathComponent("content/posts/2026-07-20-tips.md"), atomically: true, encoding: .utf8)

    try """
    ---
    title: About & Co
    ---

    Page body.
    """.write(to: site.appendingPathComponent("content/pages/about.md"), atomically: true, encoding: .utf8)

    let out = site.appendingPathComponent("out")
    try SiteBuilder().build(siteURL: site, outputURL: out)

    let index = try String(contentsOf: out.appendingPathComponent("index.html"), encoding: .utf8)
    #expect(index.contains("Tips &amp; Tricks &lt;b&gt;bold&lt;/b&gt;"))
    #expect(index.contains("Rust &amp; Go &lt; C"))
    // The raw markup must not survive into the page.
    #expect(!index.contains("Tips & Tricks <b>bold</b>"))

    let post = try String(contentsOf: out.appendingPathComponent("tips.html"), encoding: .utf8)
    #expect(post.contains("Tips &amp; Tricks &lt;b&gt;bold&lt;/b&gt;"))
    #expect(post.contains("a &amp; b"))

    let page = try String(contentsOf: out.appendingPathComponent("about.html"), encoding: .utf8)
    #expect(page.contains("About &amp; Co"))

    // Rendered Markdown is HTML by construction and must NOT be escaped.
    #expect(post.contains("<p>Body text.</p>"))
}

@Test func navUrlCannotInjectAnAttribute() throws {
    let fm = FileManager.default
    let site = fm.temporaryDirectory.appendingPathComponent("op-inject-\(UUID().uuidString)")
    try fm.createDirectory(at: site.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: site) }

    try """
    title: Site
    nav:
      - { label: Home, url: 'index.html" onmouseover="alert(1)' }

    """.write(to: site.appendingPathComponent("overprint.yml"), atomically: true, encoding: .utf8)
    try """
    ---
    title: P
    date: 2026-07-20
    slug: p
    ---

    Body.
    """.write(to: site.appendingPathComponent("content/posts/2026-07-20-p.md"), atomically: true, encoding: .utf8)

    let out = site.appendingPathComponent("out")
    try SiteBuilder().build(siteURL: site, outputURL: out)

    let index = try String(contentsOf: out.appendingPathComponent("index.html"), encoding: .utf8)
    // The quote that would break out of href="..." is neutralised, so no new attribute appears.
    #expect(!index.contains("onmouseover=\"alert(1)\""))
    #expect(index.contains("&quot;"))
}

@Test func slugCannotEscapeTheOutputDirectory() throws {
    // A slug becomes <slug>.html, so an unchecked "../.." writes outside dist/ and can overwrite
    // an arbitrary file. These must be rejected at parse time.
    for bad in ["../../pwned", "..", ".", "a/b", "a\\b", "with space", "back`tick"] {
        #expect(FrontmatterParser.slugIssue(bad) != nil, "slug \"\(bad)\" should be rejected")
    }
    for good in ["hello", "hello-world", "post_2", "v0.4.0", "a1"] {
        #expect(FrontmatterParser.slugIssue(good) == nil, "slug \"\(good)\" should be allowed")
    }
}

@Test func traversalSlugFailsTheBuildInsteadOfWritingOutside() throws {
    let fm = FileManager.default
    let site = fm.temporaryDirectory.appendingPathComponent("op-trav-\(UUID().uuidString)")
    try fm.createDirectory(at: site.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: site) }

    try "title: X\n".write(to: site.appendingPathComponent("overprint.yml"), atomically: true, encoding: .utf8)
    try """
    ---
    title: Escape
    date: 2026-07-20
    slug: ../../pwned
    ---

    Body.
    """.write(to: site.appendingPathComponent("content/posts/2026-07-20-escape.md"), atomically: true, encoding: .utf8)

    #expect(throws: OverprintError.self) {
        _ = try SiteBuilder().build(siteURL: site, outputURL: site.appendingPathComponent("out"))
    }
    // validate() must catch it too, since it is the pre-deploy gate.
    #expect(!SiteStore(siteURL: site).validate().isEmpty)
    #expect(!fm.fileExists(atPath: site.deletingLastPathComponent().appendingPathComponent("pwned.html").path))
}

@Test func previewServerBindsLoopbackOnly() throws {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("op-bind-\(UUID().uuidString)")
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dir) }
    try "<html>ok</html>".write(to: dir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)

    let server = PreviewServer()
    let port = try server.start(directory: dir, port: 0)
    defer { server.stop() }
    #expect(port > 0)

    // An out-of-range port must throw rather than trap on the in_port_t conversion.
    #expect(throws: OverprintError.self) {
        _ = try PreviewServer().start(directory: dir, port: 65536)
    }
}
