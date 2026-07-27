import Testing
@testable import OverprintKit

@Test func rendersCommonMarkdown() {
    let renderer = MarkdownRenderer()
    #expect(renderer.html("# Title").contains("<h1"))
    #expect(renderer.html("## Sub").contains("<h2"))
    #expect(renderer.html("**b**").contains("<strong>b</strong>"))
    #expect(renderer.html("*i*").contains("<em>i</em>"))
    #expect(renderer.html("`c`").contains("<code>c</code>"))
    #expect(renderer.html("> quote").contains("<blockquote>"))
    #expect(renderer.html("- one\n- two").contains("<ul>"))
    #expect(renderer.html("1. one\n2. two").contains("<ol>"))
    #expect(renderer.html("[x](https://e.com)").contains("href=\"https://e.com\""))
}

@Test func excerptTakesFirstParagraph() {
    let renderer = MarkdownRenderer()
    let excerpt = renderer.excerpt("First paragraph text.\n\nSecond paragraph.")
    #expect(excerpt == "First paragraph text.")
}

@Test func excerptTruncatesLongText() {
    let renderer = MarkdownRenderer()
    let long = String(repeating: "word ", count: 100)
    let excerpt = renderer.excerpt(long, limit: 20)
    #expect(excerpt.count <= 21) // 20 chars + ellipsis
    #expect(excerpt.hasSuffix("…"))
}
