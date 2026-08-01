import Foundation
import Yams

/// What `GitDeploy.commit` would stage right now, computed without writing anything.
///
/// Commit stages the whole site folder, so it carries drafts, while Deploy builds with
/// `includeDrafts: false`. The two differ, so the drafts are flagged rather than dropped.
public struct CommitPreview: Equatable, Sendable {
    /// One file the commit would stage.
    public struct File: Identifiable, Equatable, Sendable {
        public enum Change: String, Sendable { case added, modified, deleted, renamed }
        public enum Kind: String, Sendable { case post, page, other }

        /// Repo-relative, forward slashes: `content/posts/2026-08-01-hello.md`.
        public var path: String
        public var change: Change
        public var kind: Kind
        /// The working copy's `draft:` flag, which is what the commit would carry. False for a
        /// deleted file, which has no working copy left to read.
        public var isDraft: Bool
        /// Frontmatter title, when the file has one.
        public var title: String?

        public var id: String { path }

        public init(path: String, change: Change, kind: Kind, isDraft: Bool = false, title: String? = nil) {
            self.path = path
            self.change = change
            self.kind = kind
            self.isDraft = isDraft
            self.title = title
        }
    }

    public var isRepository: Bool
    /// The branch the commit lands on. `initializeIfNeeded` uses `main`, so a site that is not a
    /// repository yet reports the branch commit is about to create rather than nothing.
    public var branch: String
    /// Drafts first, then by path.
    public var files: [File]

    public var drafts: [File] { files.filter(\.isDraft) }
    public var isEmpty: Bool { files.isEmpty }

    public init(isRepository: Bool, branch: String, files: [File]) {
        self.isRepository = isRepository
        self.branch = branch
        self.files = files
    }

    public static func pending(siteURL: URL) throws -> CommitPreview {
        let git = GitDeploy()
        let isRepo = git.isRepository(siteURL)
        let branch = (isRepo ? git.status(siteURL: siteURL).branch : nil) ?? "main"

        var files = try git.pendingChanges(siteURL: siteURL).map {
            File(path: $0.path, change: $0.change, kind: kind(for: $0.path))
        }
        for index in files.indices where files[index].kind != .other && files[index].change != .deleted {
            let url = siteURL.appendingPathComponent(files[index].path)
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let read = FrontmatterParser.draftAndTitle(inRaw: raw)
            files[index].isDraft = read.isDraft
            files[index].title = read.title
        }
        files.sort { ($0.isDraft ? 0 : 1, $0.path) < ($1.isDraft ? 0 : 1, $1.path) }
        return CommitPreview(isRepository: isRepo, branch: branch, files: files)
    }

    /// A post or page only counts when it sits directly in its content folder. `SiteStore` reads
    /// those folders non-recursively, so Markdown one level deeper is not something the build ever
    /// renders and must not be labelled as one.
    static func kind(for path: String) -> File.Kind {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 3, parts[0] == "content", parts[2].hasSuffix(".md") else { return .other }
        switch parts[1] {
        case "posts": return .post
        case "pages": return .page
        default: return .other
        }
    }
}
