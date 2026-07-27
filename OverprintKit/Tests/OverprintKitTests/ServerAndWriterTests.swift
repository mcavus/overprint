import Testing
import Foundation
@testable import OverprintKit

@Test func createsPostWithValidFrontmatter() throws {
    let fm = FileManager.default
    let site = fm.temporaryDirectory.appendingPathComponent("pw-\(UUID().uuidString)")
    try fm.createDirectory(at: site, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: site) }

    let date = DateFormat.parse("2026-02-01")!
    let url = try PostWriter().createPost(in: site, title: "Hello World", date: date)
    #expect(url.lastPathComponent == "2026-02-01-hello-world.md")

    let raw = try String(contentsOf: url, encoding: .utf8)
    let (post, body) = try FrontmatterParser().parse(raw, filename: url.lastPathComponent)
    #expect(post.title == "Hello World")
    #expect(post.slug == "hello-world")
    #expect(post.draft == true)
    #expect(post.tags.isEmpty)
    #expect(body.contains("Start writing"))
}

@Test func newPostFilenamesAreUnique() throws {
    let fm = FileManager.default
    let site = fm.temporaryDirectory.appendingPathComponent("pw-\(UUID().uuidString)")
    try fm.createDirectory(at: site, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: site) }

    let date = DateFormat.parse("2026-02-01")!
    let writer = PostWriter()
    let first = try writer.createPost(in: site, title: "Untitled", date: date)
    let second = try writer.createPost(in: site, title: "Untitled", date: date)
    #expect(first.lastPathComponent == "2026-02-01-untitled.md")
    #expect(second.lastPathComponent == "2026-02-01-untitled-2.md")
}

@Test func frontmatterSurvivesQuotesBackslashesAndNewlines() throws {
    let fm = FileManager.default
    let site = fm.temporaryDirectory.appendingPathComponent("pw-\(UUID().uuidString)")
    try fm.createDirectory(at: site, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: site) }
    try SiteScaffolder().scaffold(at: site, title: "Escaping")

    // A backslash used to be written through unescaped, so `\"` in the file was read as an escaped
    // quote and the title ran on into the rest of the document.
    let nasty = #"The \ key, "quoted", and a"# + "\nnewline"
    let url = try PostWriter().createPost(
        in: site,
        title: nasty,
        date: DateFormat.parse("2026-02-01")!,
        tags: [#"tag with \ and ""#]
    )

    let raw = try String(contentsOf: url, encoding: .utf8)
    let (post, _) = try FrontmatterParser().parse(raw, filename: url.lastPathComponent)
    #expect(post.title == nasty)
    #expect(post.tags == [#"tag with \ and ""#])
    #expect(SiteStore(siteURL: site).validate().isEmpty)
}

@Test func yamlQuotedEscapesInTheRightOrder() {
    #expect(PostWriter.yamlQuoted("plain") == "\"plain\"")
    #expect(PostWriter.yamlQuoted(#"a"b"#) == #""a\"b""#)
    // The backslash must be escaped before the quote, or this collapses to \\" and reparses wrong.
    #expect(PostWriter.yamlQuoted(#"a\b"#) == #""a\\b""#)
    #expect(PostWriter.yamlQuoted("a\nb") == #""a\nb""#)
}

@Test func slugifyReducesToAscii() {
    #expect(PostWriter.slugify("Hello, World!") == "hello-world")
    #expect(PostWriter.slugify("  Spaces   here  ") == "spaces-here")
    #expect(PostWriter.slugify("!!!") == "untitled")
}

@Test func previewServerStartsAndStops() throws {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("srv-\(UUID().uuidString)")
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    try "<h1>Hi</h1>".write(to: dir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    defer { try? fm.removeItem(at: dir) }

    let server = PreviewServer()
    let port = try server.start(directory: dir, port: 0) // ephemeral
    defer { server.stop() }
    #expect(port > 0)
    #expect(server.isRunning)

    server.stop()
    #expect(!server.isRunning)
}
