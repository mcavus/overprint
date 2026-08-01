import Testing
import Foundation
import Swifter
@testable import OverprintKit

private func makeCarryoverSite(url: String?) throws -> URL {
    let fm = FileManager.default
    let site = fm.temporaryDirectory.appendingPathComponent("op-carry-\(UUID().uuidString)")
    try fm.createDirectory(at: site.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
    try fm.createDirectory(at: site.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
    var config = "title: Carry Site\nauthor: Ada\n"
    if let url { config += "url: \(url)\n" }
    try config.write(to: site.appendingPathComponent("overprint.yml"), atomically: true, encoding: .utf8)
    try "---\ntitle: A Post\ndate: 2026-07-20\nslug: a-post\ntags: [notes]\n---\n\nBody."
        .write(to: site.appendingPathComponent("content/posts/2026-07-20-a-post.md"),
               atomically: true, encoding: .utf8)
    try "---\ntitle: About\n---\n\nAbout body."
        .write(to: site.appendingPathComponent("content/pages/about.md"), atomically: true, encoding: .utf8)
    return site
}

/// A feed reader that has only the file needs the feed to name its own address.
@Test func feedDeclaresItsOwnAddress() throws {
    let fm = FileManager.default
    let site = try makeCarryoverSite(url: "https://blog.example.com")
    defer { try? fm.removeItem(at: site) }
    let out = site.appendingPathComponent("out")
    try SiteBuilder().build(siteURL: site, outputURL: out)

    let feed = try String(contentsOf: out.appendingPathComponent("feed.xml"), encoding: .utf8)
    #expect(feed.contains("xmlns:atom=\"http://www.w3.org/2005/Atom\""))
    #expect(feed.contains("<atom:link href=\"https://blog.example.com/feed.xml\" rel=\"self\""))
}

/// A theme can only emit a canonical link if it is told the page's own address.
@Test func everyPageKnowsItsOwnAddressAndKind() throws {
    let fm = FileManager.default
    let site = try makeCarryoverSite(url: "https://blog.example.com")
    defer { try? fm.removeItem(at: site) }
    let out = site.appendingPathComponent("out")
    let theme = site.appendingPathComponent("theme/templates")
    try fm.createDirectory(at: theme, withIntermediateDirectories: true)
    // A head override is the intended escape hatch, so it is what a real theme would use.
    try "<meta name=\"x-kind\" content=\"{{ page_kind }}\">\n<link rel=\"canonical\" href=\"{{ page_url }}\">"
        .write(to: theme.appendingPathComponent("head.html"), atomically: true, encoding: .utf8)
    try SiteBuilder().build(siteURL: site, outputURL: out)

    let expected = [
        "index.html": ("index", "https://blog.example.com/index.html"),
        "a-post.html": ("post", "https://blog.example.com/a-post.html"),
        "about.html": ("page", "https://blog.example.com/about.html"),
        "tag-notes.html": ("tag", "https://blog.example.com/tag-notes.html"),
        "404.html": ("404", "https://blog.example.com/404.html"),
    ]
    for (file, (kind, url)) in expected {
        let html = try String(contentsOf: out.appendingPathComponent(file), encoding: .utf8)
        #expect(html.contains("content=\"\(kind)\""), "\(file) kind")
        #expect(html.contains("href=\"\(url)\""), "\(file) url")
    }
}

/// Without a configured url there is nothing to be absolute against, and a relative canonical is
/// worse than none.
@Test func pageURLIsEmptyWithoutAConfiguredSiteURL() throws {
    let fm = FileManager.default
    let site = try makeCarryoverSite(url: nil)
    defer { try? fm.removeItem(at: site) }
    let out = site.appendingPathComponent("out")
    let theme = site.appendingPathComponent("theme/templates")
    try fm.createDirectory(at: theme, withIntermediateDirectories: true)
    try "{% if page_url %}<link rel=\"canonical\" href=\"{{ page_url }}\">{% endif %}"
        .write(to: theme.appendingPathComponent("head.html"), atomically: true, encoding: .utf8)
    try SiteBuilder().build(siteURL: site, outputURL: out)

    let html = try String(contentsOf: out.appendingPathComponent("a-post.html"), encoding: .utf8)
    #expect(!html.contains("rel=\"canonical\""))
}

/// A missing address previews the way the host will serve it, rather than a bare server 404.
@Test func previewServerServesTheSitesOwnNotFoundPage() throws {
    let fm = FileManager.default
    let site = try makeCarryoverSite(url: nil)
    defer { try? fm.removeItem(at: site) }
    let out = site.appendingPathComponent("out")
    try SiteBuilder().build(siteURL: site, outputURL: out)

    let response = PreviewServer.response(for: "/nothing-here", base: out)
    // The status stays 404, or a preview would hide a broken link instead of showing it.
    #expect(response.statusCode == 404)
    #expect(responseBody(response).contains("<base href="))
}

/// Falls back to a bare 404 when the build has not produced the page yet.
@Test func previewServerFallsBackWhenThereIsNoNotFoundPage() throws {
    let fm = FileManager.default
    let empty = fm.temporaryDirectory.appendingPathComponent("op-empty-\(UUID().uuidString)")
    try fm.createDirectory(at: empty, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: empty) }

    #expect(PreviewServer.response(for: "/nothing-here", base: empty).statusCode == 404)
}

/// Drains a `.raw` response's writer, which is the only way to see what it would send.
private func responseBody(_ response: HttpResponse) -> String {
    guard case .raw(_, _, _, let writer) = response, let writer else { return "" }
    let collector = BodyCollector()
    try? writer(collector)
    return String(data: collector.data, encoding: .utf8) ?? ""
}

private final class BodyCollector: HttpResponseBodyWriter {
    var data = Data()
    func write(_ file: String.File) throws {}
    func write(_ data: [UInt8]) throws { self.data.append(contentsOf: data) }
    func write(_ data: ArraySlice<UInt8>) throws { self.data.append(contentsOf: data) }
    func write(_ data: NSData) throws { self.data.append(data as Data) }
    func write(_ data: Data) throws { self.data.append(data) }
}
