import Testing
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
