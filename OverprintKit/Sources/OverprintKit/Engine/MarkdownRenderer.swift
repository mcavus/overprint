import Foundation
import Markdown

/// Renders Markdown to HTML using swift-markdown's `HTMLFormatter`, and extracts a short
/// plain-text excerpt for index listings.
public struct MarkdownRenderer {
    public init() {}

    /// Full Markdown to semantic HTML.
    public func html(_ markdown: String) -> String {
        let document = Document(parsing: markdown)
        var rewriter = HTMLRewriter()
        return HTMLFormatter.format(rewriter.visit(document) ?? document)
    }

    /// The first paragraph as plain text, trimmed to `limit` characters, for index excerpts.
    public func excerpt(_ markdown: String, limit: Int = 160) -> String {
        let document = Document(parsing: markdown)
        for child in document.children {
            if let paragraph = child as? Paragraph {
                return Self.truncate(plainText(paragraph), limit: limit)
            }
        }
        return ""
    }

    private func plainText(_ markup: Markup) -> String {
        if let text = markup as? Text { return text.string }
        if let code = markup as? InlineCode { return code.code }
        // A break is a childless leaf, so recursing into it yields nothing and glues the words on
        // either side together. A wrapped paragraph is the common case, not an edge case.
        if markup is SoftBreak || markup is LineBreak { return " " }
        return markup.children.map(plainText).joined()
    }

    static func truncate(_ string: String, limit: Int) -> String {
        // A crawler stores a meta description verbatim, so runs of whitespace are collapsed rather
        // than passed through into the attribute.
        let collapsed = string.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return trimmed[..<end].trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// Rewrites the nodes swift-markdown's `HTMLFormatter` emits without escaping or without
/// descending into their children.
///
/// The formatter interpolates text, code and attribute values straight into the output, so a `<`
/// or a `&` in ordinary prose reaches the page as markup, and a fenced block documenting HTML
/// renders that HTML instead of showing it. It also writes a heading from its plain text, which
/// drops any emphasis or inline code inside it. Replacing the nodes with raw-HTML equivalents
/// leaves the rest of the formatter alone. Only parsed nodes are replaced, so HTML a writer typed
/// deliberately still passes through, which is what Markdown promises.
private struct HTMLRewriter: MarkupRewriter {
    mutating func visitText(_ text: Text) -> Markup? {
        InlineHTML(HTMLEscape.escape(text.string))
    }

    mutating func visitInlineCode(_ code: InlineCode) -> Markup? {
        InlineHTML("<code>\(HTMLEscape.escape(code.code))</code>")
    }

    mutating func visitCodeBlock(_ block: CodeBlock) -> Markup? {
        var open = "<pre><code"
        if let language = block.language, !language.isEmpty {
            open += " class=\"language-\(HTMLEscape.escape(language))\""
        }
        return HTMLBlock(open + ">\(HTMLEscape.escape(block.code))</code></pre>")
    }

    mutating func visitHeading(_ heading: Heading) -> Markup? {
        let rebuilt = defaultVisit(heading) as? Heading ?? heading
        let inner = rebuilt.children.map { HTMLFormatter.format($0) }.joined()
        return HTMLBlock("<h\(heading.level)>\(inner)</h\(heading.level)>")
    }

    mutating func visitLink(_ link: Link) -> Markup? {
        let rebuilt = defaultVisit(link) as? Link ?? link
        let inner = rebuilt.children.map { HTMLFormatter.format($0) }.joined()
        var open = "<a"
        if let destination = link.destination, !destination.isEmpty {
            open += " href=\"\(HTMLEscape.escape(destination))\""
        }
        if let title = link.title, !title.isEmpty {
            open += " title=\"\(HTMLEscape.escape(title))\""
        }
        return InlineHTML(open + ">" + inner + "</a>")
    }

    mutating func visitImage(_ image: Image) -> Markup? {
        var tag = "<img"
        if let source = image.source, !source.isEmpty {
            tag += " src=\"\(HTMLEscape.escape(source))\""
        }
        // Always written: `alt=""` marks a decorative image, it is not a missing value.
        tag += " alt=\"\(HTMLEscape.escape(Self.altText(image)))\""
        if let title = image.title, !title.isEmpty {
            tag += " title=\"\(HTMLEscape.escape(title))\""
        }
        return InlineHTML(tag + " />")
    }

    /// The image's label with the markup removed, since `alt` is an attribute and cannot carry
    /// markup. A break becomes a space because an alt is one line of text.
    private static func altText(_ markup: Markup) -> String {
        if let text = markup as? Text { return text.string }
        if let code = markup as? InlineCode { return code.code }
        if markup is SoftBreak || markup is LineBreak { return " " }
        return markup.children.map(altText).joined()
    }
}
