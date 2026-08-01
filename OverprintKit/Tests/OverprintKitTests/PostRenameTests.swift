import Testing
import Foundation
@testable import OverprintKit

private func makePostsDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("op-rename-\(UUID().uuidString)/content/posts")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@discardableResult
private func write(_ dir: URL, _ name: String, date: String, slug: String?, title: String = "A post") throws -> URL {
    let url = dir.appendingPathComponent(name)
    var front = "title: \(title)\ndate: \(date)\ntags: []\n"
    if let slug { front += "slug: \(slug)\n" }
    front += "draft: true\n"
    try "---\n\(front)---\n\nBody.".write(to: url, atomically: true, encoding: .utf8)
    return url
}

/// The case the app produces: a post created before its title existed.
@Test func renameFollowsTheFrontmatterDateAndSlug() throws {
    let dir = try makePostsDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = try write(dir, "2026-07-30-untitled-2.md", date: "2026-08-01", slug: "website-renovation")

    let moved = try #require(try PostWriter().renameToMatchFrontmatter(url))
    #expect(moved.lastPathComponent == "2026-08-01-website-renovation.md")
    #expect(!FileManager.default.fileExists(atPath: url.path))
    #expect(FileManager.default.fileExists(atPath: moved.path))
}

@Test func renameIsANoOpWhenTheNameAlreadyMatches() throws {
    let dir = try makePostsDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = try write(dir, "2026-08-01-notes.md", date: "2026-08-01", slug: "notes")
    #expect(try PostWriter().renameToMatchFrontmatter(url) == nil)
    #expect(FileManager.default.fileExists(atPath: url.path))
}

/// A flat name is a looser convention that builds correctly, and `filenameDateIssue` deliberately
/// does not warn about it, so renaming it would be a change nobody asked for.
@Test func renameLeavesAFileWithNoDatePrefixAlone() throws {
    let dir = try makePostsDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = try write(dir, "hello.md", date: "2026-08-01", slug: nil)
    #expect(try PostWriter().renameToMatchFrontmatter(url) == nil)
    #expect(FileManager.default.fileExists(atPath: url.path))
}

/// Without a `slug:` the slug comes from the filename, so renaming would change a published URL.
@Test func renameDoesNotChangeAPublishedAddress() throws {
    let dir = try makePostsDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = try write(dir, "2026-08-01-notes.md", date: "2026-08-01", slug: nil)
    #expect(try PostWriter().renameToMatchFrontmatter(url) == nil)
}

/// Two posts claiming one slug is a duplicate `validate()` reports. Moving one onto the other
/// would destroy writing, so the file is left where it is.
@Test func renameLeavesTheFileAloneWhenTheDestinationIsTaken() throws {
    let dir = try makePostsDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    try write(dir, "2026-08-01-notes.md", date: "2026-08-01", slug: "notes", title: "The first")
    let second = try write(dir, "2026-08-01-untitled.md", date: "2026-08-01", slug: "notes", title: "The second")

    #expect(try PostWriter().renameToMatchFrontmatter(second) == nil)
    #expect(FileManager.default.fileExists(atPath: second.path))
    let kept = try String(contentsOf: dir.appendingPathComponent("2026-08-01-notes.md"), encoding: .utf8)
    #expect(kept.contains("The first"))
}

/// A slug becomes a filename, so one that climbs out of the folder must never reach disk.
@Test func renameRefusesASlugThatWouldLeaveThePostsFolder() throws {
    let dir = try makePostsDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    // `parse` rejects this slug, so the rename declines before the guard is reached.
    let url = try write(dir, "2026-08-01-untitled.md", date: "2026-08-01", slug: "../escaped")
    #expect(try PostWriter().renameToMatchFrontmatter(url) == nil)
    #expect(FileManager.default.fileExists(atPath: url.path))
    #expect(!FileManager.default.fileExists(
        atPath: dir.deletingLastPathComponent().appendingPathComponent("escaped.md").path))
}

@Test func renameIgnoresAFileItCannotParse() throws {
    let dir = try makePostsDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("2026-08-01-broken.md")
    try "no frontmatter here".write(to: url, atomically: true, encoding: .utf8)
    #expect(try PostWriter().renameToMatchFrontmatter(url) == nil)
    #expect(FileManager.default.fileExists(atPath: url.path))
}

@Test func datePrefixDetectionAcceptsOnlyAFullDate() {
    #expect(PostWriter.hasDatePrefix("2026-08-01-notes.md"))
    #expect(!PostWriter.hasDatePrefix("2026-08-01.md"))
    #expect(!PostWriter.hasDatePrefix("hello.md"))
    #expect(!PostWriter.hasDatePrefix("26-8-1-notes.md"))
    #expect(!PostWriter.hasDatePrefix("2026-aa-01-notes.md"))
}
