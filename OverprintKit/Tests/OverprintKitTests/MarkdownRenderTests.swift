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

@Test func imageKeepsItsAltText() {
    let renderer = MarkdownRenderer()
    #expect(renderer.html("![a cat](cat.jpg)").contains("<img src=\"cat.jpg\" alt=\"a cat\" />"))
    // An empty alt marks a decorative image, so the attribute is written either way.
    #expect(renderer.html("![](x.jpg)").contains("<img src=\"x.jpg\" alt=\"\" />"))
    #expect(renderer.html("![a cat](x.jpg \"the title\")")
        .contains("<img src=\"x.jpg\" alt=\"a cat\" title=\"the title\" />"))
    #expect(renderer.html("[![a cat](c.jpg)](https://e.com)")
        .contains("<a href=\"https://e.com\"><img src=\"c.jpg\" alt=\"a cat\" /></a>"))
}

/// `alt` is an attribute, so the label is flattened to its text.
@Test func altTextIsFlattenedToPlainText() {
    let renderer = MarkdownRenderer()
    #expect(renderer.html("![a *cat* and `code`](x.jpg)").contains("alt=\"a cat and code\""))
    #expect(renderer.html("![a very long\nalt text](x.jpg)").contains("alt=\"a very long alt text\""))
}

/// A fenced block is how a post shows markup rather than runs it.
@Test func codeIsEscapedRatherThanRendered() {
    let renderer = MarkdownRenderer()
    let fence = renderer.html("```\n<script>alert(1)</script>\n```")
    #expect(fence.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
    #expect(!fence.contains("<script>"))

    let inline = renderer.html("`<script>alert(1)</script>`")
    #expect(inline.contains("<code>&lt;script&gt;alert(1)&lt;/script&gt;</code>"))
    #expect(!inline.contains("<script>"))
}

/// The info string becomes an attribute value, so a quote in it would close the attribute.
@Test func fenceInfoCannotBreakOutOfTheClassAttribute() {
    let html = MarkdownRenderer().html("```js\"><script>alert(1)</script>\ncode\n```")
    #expect(html.contains("class=\"language-js&quot;&gt;&lt;script&gt;"))
    #expect(!html.contains("<script>"))
}

/// Prose is text, not markup: an unescaped `<` before a letter starts a tag and swallows what
/// follows it.
@Test func proseIsEscaped() {
    let renderer = MarkdownRenderer()
    #expect(renderer.html("Tom & Jerry, 5 < 3").contains("Tom &amp; Jerry, 5 &lt; 3"))
    #expect(renderer.html("if x <y then").contains("x &lt;y then"))
    // A written entity round-trips rather than being escaped twice.
    #expect(renderer.html("Tom &amp; Jerry").contains("Tom &amp; Jerry"))
    #expect(renderer.html("| a & b |\n|---|\n| 5 < 3 |").contains("<td>5 &lt; 3</td>"))
}

/// HTML a writer types is passed through, which is what Markdown promises. Only parsed nodes are
/// rewritten.
@Test func deliberateHTMLStillPassesThrough() {
    let renderer = MarkdownRenderer()
    #expect(renderer.html("a <b>bold</b> tag").contains("a <b>bold</b> tag"))
    #expect(renderer.html("<div class=\"note\">text</div>").contains("<div class=\"note\">"))
}

/// The formatter wrote a heading from its plain text, so inline markup inside one was lost.
@Test func headingKeepsItsInlineMarkup() {
    let renderer = MarkdownRenderer()
    #expect(renderer.html("# A *b* and `c`") == "<h1>A <em>b</em> and <code>c</code></h1>")
    #expect(renderer.html("## Tom & Jerry").contains("<h2>Tom &amp; Jerry</h2>"))
}

@Test func linkAttributesAreEscaped() {
    let renderer = MarkdownRenderer()
    #expect(renderer.html("[t](https://e.com?a=1&b=2)").contains("href=\"https://e.com?a=1&amp;b=2\""))
    #expect(renderer.html("[a *b*](x.html)").contains("<a href=\"x.html\">a <em>b</em></a>"))
    #expect(renderer.html("[t](x.html \"a title\")").contains("title=\"a title\""))
}

/// Smart punctuation converts typed quotes, but a backslash escape reaches the tag as a real one.
@Test func imageAttributesCannotBreakOutOfTheTag() {
    let renderer = MarkdownRenderer()
    let alt = renderer.html("![x\\\" onerror=\\\"alert(1)](y.jpg)")
    #expect(alt.contains("alt=\"x&quot; onerror=&quot;alert(1)\""))
    #expect(!alt.contains("onerror=\"alert"))
    #expect(renderer.html("![a](x.jpg?a=1&b=2)").contains("src=\"x.jpg?a=1&amp;b=2\""))
}
