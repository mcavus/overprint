import Testing
import Foundation
@testable import OverprintKit

/// The examples ship as bundled resources rather than a repo folder, so the tests resolve them the
/// same way the app does.
private func exampleSites() -> [URL] {
    guard let root = Bundle.module.resourceURL?.appendingPathComponent("Examples") else { return [] }
    let entries = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
    return entries.filter {
        FileManager.default.fileExists(atPath: $0.appendingPathComponent("overprint.yml").path)
    }.sorted { $0.lastPathComponent < $1.lastPathComponent }
}

/// Every shipped example must load and validate. These double as the tutorial, so a broken one
/// is a broken first impression.
@Test func shippedExamplesValidateAndBuild() throws {
    // They are bundled now, so absence is a real failure rather than a reason to skip.
    let sites = exampleSites()
    #expect(sites.count == 3, "expected the three bundled examples, found \(sites.count)")

    for site in sites {
        let name = site.lastPathComponent
        let issues = SiteStore(siteURL: site).validate()
        #expect(issues.isEmpty, "\(name) failed validation: \(issues)")

        // Build into a temp dir so the checked-in example output is left alone.
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("op-ex-\(name)-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        let summary = try SiteBuilder().build(siteURL: site, outputURL: out)
        #expect(summary.postCount > 0, "\(name) built no posts")
        #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent("index.html").path))
    }
}

/// A nav entry pointing at a page that is never generated is a dead link in the shipped tutorial.
/// Checked against a DEPLOY build (drafts excluded), which is the strictest case: a tag page whose
/// only post is a draft disappears there.
@Test func shippedExampleNavLinksAreNotDead() throws {
    for site in exampleSites() {
        let name = site.lastPathComponent
        let config = try SiteStore(siteURL: site).loadConfig()
        guard let nav = config.nav, !nav.isEmpty else { continue }

        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("op-nav-\(name)-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        try SiteBuilder().build(siteURL: site, outputURL: out, includeDrafts: false)

        for item in nav where !item.url.contains("://") {
            let target = out.appendingPathComponent(item.url)
            #expect(
                FileManager.default.fileExists(atPath: target.path),
                "\(name): nav link \"\(item.label)\" points at \(item.url), which the deploy build does not generate"
            )
        }
    }
}

/// Copying an example out must produce a writable, buildable site, since anything inside the app
/// bundle is read only and replaced on update.
@Test func copiedExampleIsWritableAndBuilds() throws {
    let library = ExampleLibrary()
    let examples = library.available()
    #expect(examples.count == 3)
    guard let first = examples.first else { return }
    #expect(!first.title.isEmpty)

    let fm = FileManager.default
    let dest = fm.temporaryDirectory.appendingPathComponent("op-copy-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: dest) }

    try library.copy(first, to: dest)
    #expect(fm.fileExists(atPath: dest.appendingPathComponent("overprint.yml").path))
    #expect(fm.isWritableFile(atPath: dest.appendingPathComponent("overprint.yml").path))

    // A new post can be written, which is the whole point of copying it out.
    try PostWriter().createPost(in: dest, title: "A new post")
    #expect(SiteStore(siteURL: dest).validate().isEmpty)
    let out = dest.appendingPathComponent("out")
    let summary = try SiteBuilder().build(siteURL: dest, outputURL: out)
    #expect(summary.postCount > 0)

    // Copying onto an existing folder must fail rather than silently merge.
    #expect(throws: OverprintError.self) { try library.copy(first, to: dest) }
}
