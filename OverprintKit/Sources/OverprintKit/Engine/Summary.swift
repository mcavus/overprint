import Foundation

/// The one-line summary a post or page shows in a listing, a feed, and its meta description.
///
/// The frontmatter `description` wins when it is set; otherwise the first paragraph is used. One
/// rule in one place, so the index card, the feed entry, and the meta tag cannot disagree.
enum Summary {
    static func text(for loaded: LoadedPost, using renderer: MarkdownRenderer, limit: Int = 160) -> String {
        if let description = loaded.post.description {
            return MarkdownRenderer.truncate(description, limit: limit)
        }
        return renderer.excerpt(loaded.body, limit: limit)
    }

    static func text(for loaded: LoadedPage, using renderer: MarkdownRenderer, limit: Int = 160) -> String {
        if let description = loaded.page.description {
            return MarkdownRenderer.truncate(description, limit: limit)
        }
        return renderer.excerpt(loaded.body, limit: limit)
    }
}
