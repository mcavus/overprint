import Foundation
import Testing
@testable import OverprintKit

/// What Commit would send to the repository, which is not what Deploy publishes.
///
/// Deploy builds with `includeDrafts: false`, so an unfinished post never reaches the site. Commit
/// stages the folder, so the same post's Markdown does reach the repository.
struct CommitPreviewTests {
    // MARK: Fixtures

    private func makeSite(_ name: String = "site") throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("op-preview-tests-\(UUID().uuidString)")
        let site = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: site.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try "title: Test site\n".write(
            to: site.appendingPathComponent("overprint.yml"), atomically: true, encoding: .utf8)
        return site
    }

    @discardableResult
    private func writePost(
        _ site: URL, _ filename: String, title: String, draft: Bool, body: String = "Body."
    ) throws -> URL {
        let url = site.appendingPathComponent("content/posts/\(filename)")
        let content = """
        ---
        title: \(title)
        date: 2026-01-01
        tags: []
        slug: \(filename.replacingOccurrences(of: ".md", with: "").dropFirst(11))
        draft: \(draft)
        ---

        \(body)
        """
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// The pairs a commit actually recorded, read back from git itself.
    private func recordedPairs(_ site: URL, args: [String]) throws -> Set<String> {
        let out = try shell(["git"] + args, in: site)
        var pairs: Set<String> = []
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let letter = parts[0].prefix(1)
            let change: String
            switch letter {
            case "A": change = "added"
            case "D": change = "deleted"
            case "R": change = "renamed"
            default: change = "modified"
            }
            pairs.insert("\(parts[1]):\(change)")
        }
        return pairs
    }

    private func previewPairs(_ preview: CommitPreview) -> Set<String> {
        Set(preview.files.map { "\($0.path):\($0.change.rawValue)" })
    }

    @discardableResult
    private func shell(_ args: [String], in dir: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.currentDirectoryURL = dir
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func commitAll(_ site: URL, _ message: String) throws {
        try GitDeploy(author: (name: "T", email: "t@example.com"))
            .commit(siteURL: site, message: message)
    }

    // MARK: Tests

    /// A porcelain entry for an unstaged change begins with a space, so reading it through a
    /// helper that trims shifts every path by one character and the draft stops being recognised
    /// as a post.
    @Test func commitPreviewReadsAPathThatStartsWithAnUnstagedMarker() throws {
        let site = try makeSite()
        try writePost(site, "2026-01-01-a.md", title: "A", draft: true)
        try commitAll(site, "first")
        try writePost(site, "2026-01-01-a.md", title: "A", draft: true, body: "Edited.")

        let preview = try CommitPreview.pending(siteURL: site)
        #expect(preview.files.count == 1)
        let file = try #require(preview.files.first)
        #expect(file.path == "content/posts/2026-01-01-a.md")
        #expect(file.change == .modified)
        #expect(file.kind == .post)
        #expect(file.isDraft)
        #expect(file.title == "A")
    }

    @Test func commitPreviewFlagsDraftsBeforeTheFirstCommit() throws {
        let site = try makeSite()
        try writePost(site, "2026-01-01-draft.md", title: "Unfinished", draft: true)
        try writePost(site, "2026-01-02-live.md", title: "Published", draft: false)
        try FileManager.default.createDirectory(
            at: site.appendingPathComponent("dist"), withIntermediateDirectories: true)
        try "<html></html>".write(
            to: site.appendingPathComponent("dist/index.html"), atomically: true, encoding: .utf8)
        try "junk".write(
            to: site.appendingPathComponent(".DS_Store"), atomically: true, encoding: .utf8)

        let preview = try CommitPreview.pending(siteURL: site)
        #expect(!preview.isRepository)
        #expect(preview.branch == "main")
        #expect(!preview.files.contains { $0.path.hasPrefix("dist/") })
        #expect(!preview.files.contains { $0.path.hasSuffix(".DS_Store") })
        #expect(preview.files.allSatisfy { $0.change == .added })
        #expect(preview.drafts.map(\.path) == ["content/posts/2026-01-01-draft.md"])
        // Drafts sort first, so the flagged rows are never the ones a capped list drops.
        #expect(preview.files.first?.isDraft == true)
    }

    /// The preview must not claim a file the commit then leaves out, or omit one it includes.
    @Test func commitPreviewMatchesTheFirstCommitExactly() throws {
        let site = try makeSite()
        try writePost(site, "2026-01-01-draft.md", title: "Unfinished", draft: true)
        try writePost(site, "2026-01-02-live.md", title: "Published", draft: false)

        let preview = try CommitPreview.pending(siteURL: site)
        try commitAll(site, "first")
        let recorded = try recordedPairs(site, args: ["show", "--pretty=format:", "--name-status", "HEAD"])
        #expect(previewPairs(preview) == recorded)
    }

    /// A first commit writes `.gitignore` itself, so only a follow-up exercises the case where the
    /// file is already on disk.
    @Test func commitPreviewMatchesAFollowUpCommitExactly() throws {
        let site = try makeSite()
        try writePost(site, "2026-01-01-a.md", title: "A", draft: false)
        try writePost(site, "2026-01-02-b.md", title: "B", draft: false)
        try commitAll(site, "first")

        try writePost(site, "2026-01-01-a.md", title: "A", draft: false, body: "Edited.")
        try FileManager.default.removeItem(at: site.appendingPathComponent("content/posts/2026-01-02-b.md"))
        try writePost(site, "2026-01-03-c.md", title: "C", draft: true,
                      body: "An entirely different draft, sharing no lines with the deleted post.")
        try FileManager.default.createDirectory(
            at: site.appendingPathComponent("dist"), withIntermediateDirectories: true)
        try "<html></html>".write(
            to: site.appendingPathComponent("dist/new.html"), atomically: true, encoding: .utf8)
        try "junk".write(
            to: site.appendingPathComponent(".DS_Store"), atomically: true, encoding: .utf8)

        let preview = try CommitPreview.pending(siteURL: site)
        try commitAll(site, "second")
        // The preview reports path-level changes, so the oracle has to as well: without this git
        // pairs the deleted post with the added one on similarity and reports a single rename.
        let recorded = try recordedPairs(
            site, args: ["diff", "--no-renames", "--name-status", "HEAD~1", "HEAD"])
        #expect(previewPairs(preview) == recorded)
        #expect(preview.drafts.map(\.path) == ["content/posts/2026-01-03-c.md"])
    }

    /// Pins `--untracked-files=all`. Under git's default the whole new folder collapses to one
    /// entry ending in a slash, and every draft inside it disappears from the report.
    @Test func commitPreviewListsEveryFileInANewFolder() throws {
        let site = try makeSite()
        try writePost(site, "2026-01-01-a.md", title: "A", draft: false)
        try commitAll(site, "first")

        let pages = site.appendingPathComponent("content/pages")
        try FileManager.default.createDirectory(at: pages, withIntermediateDirectories: true)
        for name in ["about", "colophon"] {
            try "---\ntitle: \(name)\ndraft: true\n---\n\nText."
                .write(to: pages.appendingPathComponent("\(name).md"), atomically: true, encoding: .utf8)
        }

        let preview = try CommitPreview.pending(siteURL: site)
        let paths = preview.files.map(\.path)
        #expect(paths.contains("content/pages/about.md"))
        #expect(paths.contains("content/pages/colophon.md"))
        #expect(!paths.contains { $0.hasSuffix("/") })
        #expect(preview.drafts.count == 2)
    }

    /// Pins `-z` over git's C-quoting, which would wrap this path in quotes and escape the space.
    @Test func commitPreviewHandlesAPathWithASpace() throws {
        let site = try makeSite()
        let url = site.appendingPathComponent("content/posts/2026-01-01-a b.md")
        try "---\ntitle: A B\ndate: 2026-01-01\ntags: []\nslug: a-b\ndraft: true\n---\n\nText."
            .write(to: url, atomically: true, encoding: .utf8)

        let preview = try CommitPreview.pending(siteURL: site)
        #expect(preview.files.contains { $0.path == "content/posts/2026-01-01-a b.md" && $0.isDraft })
    }

    /// A rename carries a second NUL field with the original path. Failing to consume it shifts
    /// every following entry, so this asserts the file after the rename too.
    @Test func commitPreviewReportsARenamedFileAndKeepsParsingAfterIt() throws {
        let site = try makeSite()
        try writePost(site, "2026-01-01-a.md", title: "A", draft: false)
        try writePost(site, "2026-01-09-z.md", title: "Z", draft: true)
        try commitAll(site, "first")

        try shell(["git", "mv", "content/posts/2026-01-01-a.md", "content/posts/2026-01-01-renamed.md"], in: site)
        try writePost(site, "2026-01-09-z.md", title: "Z", draft: true, body: "Edited.")

        let preview = try CommitPreview.pending(siteURL: site)
        let paths = preview.files.map(\.path)
        #expect(paths.contains("content/posts/2026-01-01-renamed.md"))
        #expect(!paths.contains("content/posts/2026-01-01-a.md"))
        // The entry after the rename must still carry its own path, not the rename's second field.
        let z = try #require(preview.files.first { $0.path == "content/posts/2026-01-09-z.md" })
        #expect(z.isDraft)
    }

    @Test func commitPreviewFlagsADraftPage() throws {
        let site = try makeSite()
        let pages = site.appendingPathComponent("content/pages")
        try FileManager.default.createDirectory(at: pages, withIntermediateDirectories: true)
        try "---\ntitle: About\ndraft: true\n---\n\nText."
            .write(to: pages.appendingPathComponent("about.md"), atomically: true, encoding: .utf8)

        let preview = try CommitPreview.pending(siteURL: site)
        let page = try #require(preview.files.first { $0.path == "content/pages/about.md" })
        #expect(page.kind == .page)
        #expect(page.isDraft)
        #expect(page.title == "About")
    }

    /// A post that fails validation is exactly when the warning matters, so the draft flag is read
    /// leniently rather than through the validating parser.
    @Test func commitPreviewReadsTheDraftFlagFromInvalidFrontmatter() throws {
        let site = try makeSite()
        try "---\ndraft: true\n---\n\nNo title, no date."
            .write(to: site.appendingPathComponent("content/posts/2026-01-01-broken.md"),
                   atomically: true, encoding: .utf8)

        let preview = try CommitPreview.pending(siteURL: site)
        let file = try #require(preview.files.first { $0.path.hasSuffix("broken.md") })
        #expect(file.isDraft)
        #expect(file.title == nil)
        // The file really is invalid, which is what makes the lenient read necessary.
        #expect(!SiteStore(siteURL: site).validate().isEmpty)
    }

    /// `SiteStore` reads the content folders non-recursively, so Markdown one level deeper is never
    /// rendered and must not be labelled a post.
    @Test func commitPreviewDoesNotClassifyNestedMarkdownAsAPost() throws {
        let site = try makeSite()
        let nested = site.appendingPathComponent("content/posts/drafts")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "---\ntitle: Nested\ndraft: true\n---\n\nText."
            .write(to: nested.appendingPathComponent("x.md"), atomically: true, encoding: .utf8)

        let preview = try CommitPreview.pending(siteURL: site)
        let file = try #require(preview.files.first { $0.path.hasSuffix("drafts/x.md") })
        #expect(file.kind == .other)
        #expect(!file.isDraft)
    }

    @Test func commitPreviewIsEmptyOnACleanRepository() throws {
        let site = try makeSite()
        try writePost(site, "2026-01-01-a.md", title: "A", draft: false)
        try commitAll(site, "first")

        let preview = try CommitPreview.pending(siteURL: site)
        #expect(preview.isEmpty)
        #expect(preview.isRepository)
        #expect(preview.branch == "main")
    }
}
