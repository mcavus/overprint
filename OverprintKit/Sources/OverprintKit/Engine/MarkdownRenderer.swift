import Foundation
import Markdown

/// Renders Markdown to HTML using swift-markdown's `HTMLFormatter`, and extracts a short
/// plain-text excerpt for index listings.
public struct MarkdownRenderer {
    public init() {}

    /// Full Markdown to semantic HTML.
    public func html(_ markdown: String) -> String {
        HTMLFormatter.format(markdown)
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
        return markup.children.map(plainText).joined()
    }

    static func truncate(_ string: String, limit: Int) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return trimmed[..<end].trimmingCharacters(in: .whitespaces) + "…"
    }
}
