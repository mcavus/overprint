import Testing
import Foundation
@testable import OverprintKit

/// Runs git directly, for test setup and inspection (separate from the code under test).
@discardableResult
private func git(_ args: [String], in dir: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = args
    process.currentDirectoryURL = dir
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if process.terminationStatus != 0 {
        throw NSError(domain: "git", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: output])
    }
    return output
}

private let testAuthor = (name: "Test", email: "test@example.com")

@Test func commitInitializesRepoAndIgnoresDist() throws {
    let fm = FileManager.default
    let site = fm.temporaryDirectory.appendingPathComponent("op-git-\(UUID().uuidString)")
    let posts = site.appendingPathComponent("content/posts")
    try fm.createDirectory(at: posts, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: site) }

    try "title: Blog\n".write(to: site.appendingPathComponent("overprint.yml"), atomically: true, encoding: .utf8)
    try "---\ntitle: P\ndate: 2026-01-01\nslug: p\n---\n\nHi."
        .write(to: posts.appendingPathComponent("2026-01-01-p.md"), atomically: true, encoding: .utf8)
    // A generated dist/ that must NOT be committed.
    let dist = site.appendingPathComponent("dist")
    try fm.createDirectory(at: dist, withIntermediateDirectories: true)
    try "<html></html>".write(to: dist.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)

    let deploy = GitDeploy(author: testAuthor)
    try deploy.commit(siteURL: site, message: "Initial commit")

    #expect(deploy.isRepository(site))
    let gitignore = try String(contentsOf: site.appendingPathComponent(".gitignore"), encoding: .utf8)
    #expect(gitignore.contains("dist/"))

    let tracked = try git(["ls-files"], in: site)
    #expect(tracked.contains("overprint.yml"))
    #expect(tracked.contains("content/posts/2026-01-01-p.md"))
    #expect(!tracked.contains("dist/"))

    let log = try git(["log", "--oneline"], in: site)
    #expect(log.contains("Initial commit"))

    let status = deploy.status(siteURL: site)
    #expect(status.isRepository)
    #expect(status.hasChanges == false)
}

@Test func commitNothingToCommitThrows() throws {
    let fm = FileManager.default
    let site = fm.temporaryDirectory.appendingPathComponent("op-git-\(UUID().uuidString)")
    try fm.createDirectory(at: site.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: site) }
    try "title: Blog\n".write(to: site.appendingPathComponent("overprint.yml"), atomically: true, encoding: .utf8)

    let deploy = GitDeploy(author: testAuthor)
    try deploy.commit(siteURL: site, message: "Initial")
    #expect(throws: GitDeploy.GitError.self) {
        try deploy.commit(siteURL: site, message: "again")
    }
}

@Test func pushSourceSendsCommitsToRemoteAndAccumulates() throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent("op-push-\(UUID().uuidString)")
    let site = base.appendingPathComponent("site")
    try fm.createDirectory(at: site.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: base) }

    let bare = base.appendingPathComponent("remote.git")
    try git(["init", "--bare", bare.path], in: base)

    let deploy = GitDeploy(author: testAuthor)
    let posts = site.appendingPathComponent("content/posts")
    try "title: Blog\n".write(to: site.appendingPathComponent("overprint.yml"), atomically: true, encoding: .utf8)
    try "---\ntitle: One\ndate: 2026-01-01\nslug: one\n---\n\nFirst."
        .write(to: posts.appendingPathComponent("2026-01-01-one.md"), atomically: true, encoding: .utf8)

    try deploy.commit(siteURL: site, message: "First post")
    try deploy.setRemote(siteURL: site, url: bare.path)
    try deploy.pushSource(siteURL: site)

    // The source branch exists on the remote with the first commit.
    let heads = try git(["ls-remote", "--heads", bare.path], in: base)
    #expect(heads.contains("refs/heads/main"))
    #expect(try git(["--git-dir", bare.path, "rev-list", "--count", "main"], in: base) == "1")

    // A second commit accumulates rather than replacing (unlike gh-pages).
    try "---\ntitle: Two\ndate: 2026-01-02\nslug: two\n---\n\nSecond."
        .write(to: posts.appendingPathComponent("2026-01-02-two.md"), atomically: true, encoding: .utf8)
    try deploy.commit(siteURL: site, message: "Second post")
    try deploy.pushSource(siteURL: site)

    #expect(try git(["--git-dir", bare.path, "rev-list", "--count", "main"], in: base) == "2")
    let log = try git(["--git-dir", bare.path, "log", "--oneline", "main"], in: base)
    #expect(log.contains("First post"))
    #expect(log.contains("Second post"))
    // Source pushes must never carry dist/.
    let tree = try git(["--git-dir", bare.path, "ls-tree", "-r", "main", "--name-only"], in: base)
    #expect(!tree.contains("dist/"))
}

@Test func hasCommitsReflectsRepoState() throws {
    let fm = FileManager.default
    let site = fm.temporaryDirectory.appendingPathComponent("op-hc-\(UUID().uuidString)")
    try fm.createDirectory(at: site, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: site) }

    let deploy = GitDeploy(author: testAuthor)
    #expect(!deploy.hasCommits(site)) // not a repo yet
    try deploy.initializeIfNeeded(siteURL: site)
    #expect(!deploy.hasCommits(site)) // initialized, but no commit
    try "title: X\n".write(to: site.appendingPathComponent("overprint.yml"), atomically: true, encoding: .utf8)
    try deploy.commit(siteURL: site, message: "First")
    #expect(deploy.hasCommits(site))
}

@Test func setRemoteUpdatesExistingOrigin() throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent("op-remote-\(UUID().uuidString)")
    let site = base.appendingPathComponent("site")
    try fm.createDirectory(at: site, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: base) }

    let deploy = GitDeploy(author: testAuthor)
    try deploy.initializeIfNeeded(siteURL: site)
    try deploy.setRemote(siteURL: site, url: "https://example.com/a.git")
    #expect(deploy.status(siteURL: site).remoteURL == "https://example.com/a.git")
    try deploy.setRemote(siteURL: site, url: "https://example.com/b.git")
    #expect(deploy.status(siteURL: site).remoteURL == "https://example.com/b.git")
}

@Test func publishPushesDistToGhPages() throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent("op-pub-\(UUID().uuidString)")
    try fm.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: base) }

    let dist = base.appendingPathComponent("dist")
    try fm.createDirectory(at: dist.appendingPathComponent("assets"), withIntermediateDirectories: true)
    try "<html>hello</html>".write(to: dist.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    try "body{}".write(to: dist.appendingPathComponent("assets/style.css"), atomically: true, encoding: .utf8)

    let bare = base.appendingPathComponent("remote.git")
    try git(["init", "--bare", bare.path], in: base)

    try GitDeploy(author: testAuthor).publish(distURL: dist, remote: bare.path, branch: "gh-pages", cname: "blog.example.com")

    let tree = try git(["--git-dir", bare.path, "ls-tree", "-r", "gh-pages", "--name-only"], in: base)
    #expect(tree.contains("index.html"))
    #expect(tree.contains("assets/style.css"))
    #expect(tree.contains("CNAME"))
    #expect(tree.contains(".nojekyll"))

    let cname = try git(["--git-dir", bare.path, "show", "gh-pages:CNAME"], in: base)
    #expect(cname == "blog.example.com")
}

@Test func redeployForceUpdatesSingleCommit() throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent("op-redeploy-\(UUID().uuidString)")
    try fm.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: base) }

    let dist = base.appendingPathComponent("dist")
    try fm.createDirectory(at: dist, withIntermediateDirectories: true)
    let bare = base.appendingPathComponent("remote.git")
    try git(["init", "--bare", bare.path], in: base)
    let deploy = GitDeploy(author: testAuthor)

    try "<html>one</html>".write(to: dist.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    try deploy.publish(distURL: dist, remote: bare.path)

    try "<html>two</html>".write(to: dist.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    try deploy.publish(distURL: dist, remote: bare.path)

    let content = try git(["--git-dir", bare.path, "show", "gh-pages:index.html"], in: base)
    #expect(content.contains("two"))
    // Force-push keeps gh-pages at a single commit.
    let count = try git(["--git-dir", bare.path, "rev-list", "--count", "gh-pages"], in: base)
    #expect(count == "1")
}

/// Opt-in end-to-end deploy against a real remote. Skipped unless OVERPRINT_DEPLOY_REMOTE is set,
/// so the normal suite stays offline. Run against a THROWAWAY repo only:
///   OVERPRINT_DEPLOY_REMOTE=https://github.com/<user>/<throwaway>.git swift test --filter realDeployToRemote
@Test(.enabled(if: ProcessInfo.processInfo.environment["OVERPRINT_DEPLOY_REMOTE"] != nil))
func realDeployToRemote() throws {
    let remote = ProcessInfo.processInfo.environment["OVERPRINT_DEPLOY_REMOTE"]!
    let fm = FileManager.default
    let site = fm.temporaryDirectory.appendingPathComponent("op-real-\(UUID().uuidString)")
    let posts = site.appendingPathComponent("content/posts")
    try fm.createDirectory(at: posts, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: site) }

    try "title: Overprint Deploy Test\nauthor: Test Author\ndescription: deploy smoke test\n"
        .write(to: site.appendingPathComponent("overprint.yml"), atomically: true, encoding: .utf8)
    try """
    ---
    title: Hello from Overprint
    date: 2026-07-19
    slug: hello
    tags: [test]
    ---

    This page was published by Overprint's deploy.
    """.write(to: posts.appendingPathComponent("2026-07-19-hello.md"), atomically: true, encoding: .utf8)

    try SiteBuilder().build(siteURL: site, includeDrafts: false)
    // Uses the machine's global git identity, exactly like the app does.
    try GitDeploy().publish(
        distURL: site.appendingPathComponent("dist"),
        remote: remote,
        branch: "gh-pages",
        message: "Overprint deploy test"
    )
}

@Test func publishRefusesProtectedBranchesAndLeavesThemIntact() throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent("op-protect-\(UUID().uuidString)")
    let site = base.appendingPathComponent("site")
    try fm.createDirectory(at: site.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: base) }

    let bare = base.appendingPathComponent("remote.git")
    try git(["init", "--bare", bare.path], in: base)
    let deploy = GitDeploy(author: testAuthor)

    // Put real source history on main.
    try "title: Blog\n".write(to: site.appendingPathComponent("overprint.yml"), atomically: true, encoding: .utf8)
    try deploy.commit(siteURL: site, message: "Real source history")
    try deploy.setRemote(siteURL: site, url: bare.path)
    try deploy.pushSource(siteURL: site)
    let before = try git(["--git-dir", bare.path, "rev-parse", "main"], in: base)

    // A dist to publish.
    let dist = base.appendingPathComponent("dist")
    try fm.createDirectory(at: dist, withIntermediateDirectories: true)
    try "<html>built</html>".write(to: dist.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)

    for branch in ["main", "master", "MAIN", " main "] {
        #expect(throws: GitDeploy.GitError.self) {
            try deploy.publish(distURL: dist, remote: bare.path, branch: branch)
        }
    }
    // A custom source branch name is protected too when the caller says so.
    #expect(throws: GitDeploy.GitError.self) {
        try deploy.publish(distURL: dist, remote: bare.path, branch: "writing", alsoProtecting: ["writing"])
    }

    // Source history on the remote is byte-for-byte untouched.
    #expect(try git(["--git-dir", bare.path, "rev-parse", "main"], in: base) == before)
    let log = try git(["--git-dir", bare.path, "log", "--oneline", "main"], in: base)
    #expect(log.contains("Real source history"))

    // gh-pages still works.
    try deploy.publish(distURL: dist, remote: bare.path, branch: "gh-pages")
    #expect(try git(["ls-remote", "--heads", bare.path], in: base).contains("gh-pages"))
}

@Test func publishWithoutDistThrows() throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent("op-nodist-\(UUID().uuidString)")
    try fm.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: base) }
    let missing = base.appendingPathComponent("dist")
    #expect(throws: GitDeploy.GitError.self) {
        try GitDeploy(author: testAuthor).publish(distURL: missing, remote: base.appendingPathComponent("r.git").path)
    }
}

@Test func customDomainClaimsOnlyAHostThisSiteOwns() {
    // A host at the root of the url is ours to claim, with or without a trailing slash.
    #expect(GitDeploy.customDomain(from: "https://blog.example.com") == "blog.example.com")
    #expect(GitDeploy.customDomain(from: "https://blog.example.com/") == "blog.example.com")
    #expect(GitDeploy.customDomain(from: "blog.example.com") == "blog.example.com")

    // A path means another site owns the host.
    #expect(GitDeploy.customDomain(from: "https://example.com/blog") == nil)
    #expect(GitDeploy.customDomain(from: "https://example.com/blog/") == nil)
    #expect(GitDeploy.customDomain(from: "https://example.com/a/b") == nil)
    #expect(GitDeploy.customDomain(from: "example.com/blog") == nil)

    // A github.io address needs no custom domain.
    #expect(GitDeploy.customDomain(from: "https://ada.github.io") == nil)
    #expect(GitDeploy.customDomain(from: "https://ada.github.io/notes") == nil)

    #expect(GitDeploy.customDomain(from: "") == nil)
    #expect(GitDeploy.customDomain(from: "   ") == nil)
}

@Test func publishWritesNoCNAMEForASiteUnderAnotherHost() throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent("op-subdir-\(UUID().uuidString)")
    try fm.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: base) }

    let dist = base.appendingPathComponent("dist")
    try fm.createDirectory(at: dist, withIntermediateDirectories: true)
    try "<html>hello</html>".write(to: dist.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)

    let bare = base.appendingPathComponent("remote.git")
    try git(["init", "--bare", bare.path], in: base)

    let cname = GitDeploy.customDomain(from: "https://example.com/blog")
    try GitDeploy(author: testAuthor).publish(distURL: dist, remote: bare.path, branch: "gh-pages", cname: cname)

    let tree = try git(["--git-dir", bare.path, "ls-tree", "-r", "gh-pages", "--name-only"], in: base)
    #expect(!tree.contains("CNAME"))
    #expect(tree.contains("index.html"))
    #expect(tree.contains(".nojekyll"))
}
