import Testing
import Foundation
@testable import OverprintKit

/// A site with one published post and one draft.
private func makeSiteWithADraft() throws -> URL {
    let fm = FileManager.default
    let site = fm.temporaryDirectory.appendingPathComponent("op-race-\(UUID().uuidString)")
    try fm.createDirectory(at: site.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
    try "title: Race\nauthor: Ada\nurl: https://race.example.com\n"
        .write(to: site.appendingPathComponent("overprint.yml"), atomically: true, encoding: .utf8)
    try """
    ---
    title: Published
    date: 2026-07-20
    slug: published
    tags: []
    draft: false
    ---

    Real.
    """.write(to: site.appendingPathComponent("content/posts/2026-07-20-published.md"),
              atomically: true, encoding: .utf8)
    try """
    ---
    title: Secret Draft
    date: 2026-07-21
    slug: secret
    tags: []
    draft: true
    ---

    Please do not publish this.
    """.write(to: site.appendingPathComponent("content/posts/2026-07-21-secret.md"),
              atomically: true, encoding: .utf8)
    return site
}

/// Shows why a deploy cannot publish from `site/dist`.
///
/// `dist/` is shared with the preview builds driven by the file watcher and by autosave, which
/// pass `includeDrafts: true` and which delete and recreate the directory. A rebuild landing
/// between a deploy's build and its publish replaces the output that would be published.
@Test func aCompetingPreviewBuildContaminatesTheSharedDistDirectory() throws {
    let site = try makeSiteWithADraft()
    defer { try? FileManager.default.removeItem(at: site) }
    let dist = site.appendingPathComponent("dist")

    try SiteBuilder().build(siteURL: site, includeDrafts: false)
    #expect(!FileManager.default.fileExists(atPath: dist.appendingPathComponent("secret.html").path))

    // The watcher or an autosave firing mid-deploy.
    try SiteBuilder().build(siteURL: site, includeDrafts: true)

    // Anything publishing from dist/ at this point would ship the draft.
    #expect(FileManager.default.fileExists(atPath: dist.appendingPathComponent("secret.html").path))
    let index = try String(contentsOf: dist.appendingPathComponent("index.html"), encoding: .utf8)
    #expect(index.contains("Secret Draft"))
    // The feed is built from published posts either way, so a contaminated dist/ exposes drafts
    // as pages and index rows but not in the feed.
    let feed = try String(contentsOf: dist.appendingPathComponent("feed.xml"), encoding: .utf8)
    #expect(!feed.contains("Secret Draft"))
}

/// A deploy builds into a directory of its own, so no other build can reach it.
@Test func aStagedBuildIsUnreachableByOtherBuilds() throws {
    let site = try makeSiteWithADraft()
    defer { try? FileManager.default.removeItem(at: site) }
    let staging = FileManager.default.temporaryDirectory
        .appendingPathComponent("op-stage-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: staging) }

    try SiteBuilder().build(siteURL: site, outputURL: staging, includeDrafts: false)

    // Repeated preview builds against the shared directory.
    for _ in 0..<3 { try SiteBuilder().build(siteURL: site, includeDrafts: true) }

    // The payload that would be published is untouched.
    let fm = FileManager.default
    #expect(!fm.fileExists(atPath: staging.appendingPathComponent("secret.html").path))
    #expect(fm.fileExists(atPath: staging.appendingPathComponent("published.html").path))
    let index = try String(contentsOf: staging.appendingPathComponent("index.html"), encoding: .utf8)
    #expect(!index.contains("Secret Draft"))
    #expect(index.contains("Published"))
    let feed = try String(contentsOf: staging.appendingPathComponent("feed.xml"), encoding: .utf8)
    let sitemap = try String(contentsOf: staging.appendingPathComponent("sitemap.xml"), encoding: .utf8)
    #expect(!feed.contains("secret"))
    #expect(!sitemap.contains("secret"))

    // Meanwhile dist/ is contaminated, proving the two really are independent.
    #expect(fm.fileExists(atPath: site.appendingPathComponent("dist/secret.html").path))
}

// MARK: The whole deploy path, against a real repository

@discardableResult
private func rawGit(_ args: [String], in dir: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = args
    process.currentDirectoryURL = dir
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if process.terminationStatus != 0 {
        throw NSError(domain: "git", code: Int(process.terminationStatus),
                      userInfo: [NSLocalizedDescriptionKey: out])
    }
    return out
}

/// End to end: what lands on the publish branch when a preview build races the deploy.
///
/// Runs the full deploy sequence with a draft-inclusive build in the middle, then clones the
/// published branch back and inspects it rather than trusting the local directory.
@Test func publishingDuringAPreviewRebuildShipsNoDrafts() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("op-deploy-\(UUID().uuidString)")
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    let site = try makeSiteWithADraft()
    defer { try? fm.removeItem(at: site) }

    let remote = root.appendingPathComponent("origin.git")
    try fm.createDirectory(at: remote, withIntermediateDirectories: true)
    try rawGit(["init", "--bare", "-b", "main", "."], in: remote)

    let deploy = GitDeploy(author: (name: "Test", email: "test@example.com"))
    try deploy.commit(siteURL: site, message: "Initial commit")
    try deploy.setRemote(siteURL: site, url: remote.path)
    try deploy.pushSource(siteURL: site)

    // What deploy does now: build the payload somewhere private.
    let staging = root.appendingPathComponent("staging")
    try SiteBuilder().build(siteURL: site, outputURL: staging, includeDrafts: false)

    // The watcher and autosave, firing while the push is in flight.
    try SiteBuilder().build(siteURL: site, includeDrafts: true)
    try SiteBuilder().build(siteURL: site, includeDrafts: true)

    try deploy.publish(distURL: staging, remote: remote.path, branch: "gh-pages",
                       cname: nil, alsoProtecting: ["main"])

    // Inspect what is actually on the branch, not what is on disk locally.
    let checkout = root.appendingPathComponent("published")
    try rawGit(["clone", "--branch", "gh-pages", "--single-branch", remote.path, checkout.path], in: root)

    #expect(!fm.fileExists(atPath: checkout.appendingPathComponent("secret.html").path))
    #expect(fm.fileExists(atPath: checkout.appendingPathComponent("published.html").path))

    let index = try String(contentsOf: checkout.appendingPathComponent("index.html"), encoding: .utf8)
    #expect(!index.contains("Secret Draft"))
    #expect(index.contains("Published"))

    let feed = try String(contentsOf: checkout.appendingPathComponent("feed.xml"), encoding: .utf8)
    let sitemap = try String(contentsOf: checkout.appendingPathComponent("sitemap.xml"), encoding: .utf8)
    #expect(!feed.contains("secret"))
    #expect(!sitemap.contains("secret"))

    // No draft reached the branch in any form.
    let published = try rawGit(["ls-tree", "-r", "--name-only", "HEAD"], in: checkout)
    #expect(!published.contains("secret"))
}
