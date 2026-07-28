import Testing
import Foundation
@testable import OverprintKit

@Test func parsesValidFrontmatter() throws {
    let raw = """
    ---
    title: Hello
    date: 2026-07-16
    tags: [a, b]
    slug: hello
    draft: true
    ---

    Body here.
    """
    let (post, body) = try FrontmatterParser().parse(raw, filename: "2026-07-16-hello.md")
    #expect(post.title == "Hello")
    #expect(DateFormat.isoString(post.date) == "2026-07-16")
    #expect(post.tags == ["a", "b"])
    #expect(post.slug == "hello")
    #expect(post.draft)
    #expect(body.contains("Body here."))
}

@Test func missingTitleAndDateThrows() {
    let raw = "---\nslug: x\n---\nbody"
    #expect(throws: OverprintError.self) {
        _ = try FrontmatterParser().parse(raw, filename: "x.md")
    }
}

@Test func slugFallsBackToFilename() throws {
    let raw = "---\ntitle: T\ndate: 2026-01-01\n---\nbody"
    let (post, _) = try FrontmatterParser().parse(raw, filename: "2026-01-01-my-post.md")
    #expect(post.slug == "my-post")
}

@Test func missingFrontmatterFenceThrows() {
    let raw = "no frontmatter here"
    #expect(throws: OverprintError.self) {
        _ = try FrontmatterParser().parse(raw, filename: "x.md")
    }
}

@Test func draftDefaultsToFalse() throws {
    let raw = "---\ntitle: T\ndate: 2026-01-01\nslug: t\n---\nbody"
    let (post, _) = try FrontmatterParser().parse(raw, filename: "2026-01-01-t.md")
    #expect(post.draft == false)
}

@Test func validateCatchesAFilenameDateThatDisagreesWithTheField() throws {
    let fm = FileManager.default
    let site = fm.temporaryDirectory.appendingPathComponent("op-fd-\(UUID().uuidString)")
    try fm.createDirectory(at: site.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: site) }
    try "title: Dates\nauthor: Ada\n"
        .write(to: site.appendingPathComponent("overprint.yml"), atomically: true, encoding: .utf8)
    // Filename says 2026-06-08, frontmatter says 2020-01-01. This used to validate clean.
    try """
    ---
    title: Mismatched
    date: 2020-01-01
    slug: mismatched
    tags: []
    draft: false
    ---

    Body.
    """.write(to: site.appendingPathComponent("content/posts/2026-06-08-mismatched.md"),
              atomically: true, encoding: .utf8)

    let issues = SiteStore(siteURL: site).validate()
    #expect(issues.count == 1)
    #expect(issues.first?.description.contains("2026-06-08") == true)
    #expect(issues.first?.description.contains("2020-01-01") == true)
}

@Test func filenameDateIssueIsQuietWhenItShouldBe() {
    let date = DateFormat.parse("2026-06-08")!
    // Agreement.
    #expect(FrontmatterParser.filenameDateIssue(filename: "2026-06-08-hello.md", date: date) == nil)
    // No prefix at all is a looser convention question, not an error.
    #expect(FrontmatterParser.filenameDateIssue(filename: "hello.md", date: date) == nil)
    // Disagreement.
    #expect(FrontmatterParser.filenameDateIssue(filename: "2020-01-01-hello.md", date: date) != nil)
}
