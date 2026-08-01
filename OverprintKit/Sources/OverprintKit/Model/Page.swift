import Foundation

/// A standalone page (About, Colophon, and so on), as opposed to a dated post.
///
/// On disk a page lives at `content/pages/<slug>.md` with YAML frontmatter: `title`, and
/// optionally `slug` and `draft`. Pages have no date: they are not part of the post timeline,
/// so they never appear in the index list, the RSS feed, or tag pages.
public struct Page: Equatable, Sendable {
    public var title: String
    public var slug: String
    public var draft: Bool
    /// Optional override for the page's meta description.
    public var description: String?

    public init(title: String, slug: String, draft: Bool = false, description: String? = nil) {
        self.title = title
        self.slug = slug
        self.draft = draft
        self.description = description
    }
}

/// A parsed page paired with its raw Markdown body and source location.
public struct LoadedPage: Equatable, Sendable {
    public var page: Page
    public var body: String
    public var sourceURL: URL

    public init(page: Page, body: String, sourceURL: URL) {
        self.page = page
        self.body = body
        self.sourceURL = sourceURL
    }
}
