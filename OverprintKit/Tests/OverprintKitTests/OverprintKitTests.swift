import Testing
@testable import OverprintKit

@Test func versionIsNotEmpty() {
    #expect(!Overprint.version.isEmpty)
}

@Test func postStoresFrozenFrontmatterFields() {
    let post = Post(title: "Hello", date: DateFormat.parse("2026-07-16")!, tags: ["intro"], slug: "hello", draft: true)
    #expect(post.title == "Hello")
    #expect(DateFormat.isoString(post.date) == "2026-07-16")
    #expect(post.tags == ["intro"])
    #expect(post.slug == "hello")
    #expect(post.draft)
}
