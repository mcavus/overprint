import Foundation

/// A single blog post, matching the frozen frontmatter contract.
///
/// On disk a post lives at `content/posts/YYYY-MM-DD-slug.md` with YAML frontmatter:
/// `title`, `date` (YYYY-MM-DD), `tags`, `slug`, `draft`.
public struct Post: Equatable, Sendable {
    public var title: String
    public var date: Date
    public var tags: [String]
    public var slug: String
    public var draft: Bool
    /// Optional override for the summary shown in listings, the feed, and the page's meta
    /// description. Absent means the first paragraph is used.
    public var description: String?

    public init(
        title: String,
        date: Date,
        tags: [String] = [],
        slug: String,
        draft: Bool = false,
        description: String? = nil
    ) {
        self.title = title
        self.date = date
        self.tags = tags
        self.slug = slug
        self.draft = draft
        self.description = description
    }
}

/// A parsed post paired with its raw Markdown body and source location.
public struct LoadedPost: Equatable, Sendable {
    public var post: Post
    public var body: String
    public var sourceURL: URL

    public init(post: Post, body: String, sourceURL: URL) {
        self.post = post
        self.body = body
        self.sourceURL = sourceURL
    }
}
