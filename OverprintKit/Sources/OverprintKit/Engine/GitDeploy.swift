import Foundation

/// Git operations for Commit and Deploy, shelling out to the system `git` (no dependency).
/// The source lives on the site repo's working branch; Deploy publishes the built `dist/` to a
/// `gh-pages` branch via a single-commit force-push, so the branch never accumulates churn.
public struct GitDeploy: Sendable {
    /// An optional committer identity. Nil uses the machine's global git config (the normal app
    /// path); tests pass one so temp repos can commit without global config.
    public var author: (name: String, email: String)?

    public init(author: (name: String, email: String)? = nil) {
        self.author = author
    }

    public struct Status: Sendable, Equatable {
        public var isRepository: Bool
        public var branch: String?
        public var remoteURL: String?
        public var hasChanges: Bool

        public init(isRepository: Bool, branch: String?, remoteURL: String?, hasChanges: Bool) {
            self.isRepository = isRepository
            self.branch = branch
            self.remoteURL = remoteURL
            self.hasChanges = hasChanges
        }
    }

    public enum GitError: Error, LocalizedError {
        case gitNotFound
        case failed(String)
        case nothingToCommit
        case noDist

        public var errorDescription: String? {
            switch self {
            case .gitNotFound: return "git was not found. Install the Xcode command line tools."
            case .failed(let message): return message.isEmpty ? "git reported an error." : message
            case .nothingToCommit: return "Nothing to commit; the working tree is clean."
            case .noDist: return "No built site to deploy. Build it first."
            }
        }
    }

    // MARK: Queries

    public func isRepository(_ siteURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: siteURL.appendingPathComponent(".git").path)
    }

    public func status(siteURL: URL) -> Status {
        guard isRepository(siteURL) else {
            return Status(isRepository: false, branch: nil, remoteURL: nil, hasChanges: false)
        }
        let branch = try? run(["rev-parse", "--abbrev-ref", "HEAD"], in: siteURL)
        let remote = try? run(["remote", "get-url", "origin"], in: siteURL)
        let porcelain = (try? run(["status", "--porcelain"], in: siteURL)) ?? ""
        return Status(
            isRepository: true,
            branch: branch?.isEmpty == false ? branch : nil,
            remoteURL: remote?.isEmpty == false ? remote : nil,
            hasChanges: !porcelain.isEmpty
        )
    }

    // MARK: Commit

    /// Initializes a repo if needed, stages the source (respecting `.gitignore`, which excludes
    /// `dist/`), and commits with `message`. Throws `.nothingToCommit` when the tree is clean.
    public func commit(siteURL: URL, message: String) throws {
        try initializeIfNeeded(siteURL: siteURL)
        try ensureGitignore(siteURL)
        try run(["add", "-A"], in: siteURL)
        let staged = try run(["status", "--porcelain"], in: siteURL)
        if staged.isEmpty { throw GitError.nothingToCommit }
        try run(identityArgs + ["commit", "-m", message], in: siteURL)
    }

    /// Whether the repo has at least one commit (a freshly initialized repo has none).
    public func hasCommits(_ siteURL: URL) -> Bool {
        (try? run(["rev-parse", "--verify", "HEAD"], in: siteURL)) != nil
    }

    /// Points `origin` at `url`, adding the remote or updating it if it already exists.
    public func setRemote(siteURL: URL, url: String) throws {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let existing = try? run(["remote", "get-url", "origin"], in: siteURL)
        if let existing, !existing.isEmpty {
            if existing != trimmed { try run(["remote", "set-url", "origin", trimmed], in: siteURL) }
        } else {
            try run(["remote", "add", "origin", trimmed], in: siteURL)
        }
    }

    /// Pushes the current branch to `origin`, setting upstream on the first push. Deliberately
    /// never force-pushes: source history is real history, unlike the generated `gh-pages`.
    public func pushSource(siteURL: URL) throws {
        let branch = try run(["rev-parse", "--abbrev-ref", "HEAD"], in: siteURL)
        guard !branch.isEmpty, branch != "HEAD" else {
            throw GitError.failed("Could not determine the current branch.")
        }
        try run(["push", "-u", "origin", branch], in: siteURL)
    }

    public func initializeIfNeeded(siteURL: URL, defaultBranch: String = "main") throws {
        guard !isRepository(siteURL) else { return }
        try run(["init", "-b", defaultBranch], in: siteURL)
        try ensureGitignore(siteURL)
    }

    // MARK: Deploy

    /// The host to write into `CNAME` for `url`, or nil when the domain is not this site's to claim.
    ///
    /// A `CNAME` claims a whole host for one repository. Nil for a `github.io` address, which needs
    /// no custom domain, and nil when `url` carries a path: a path means the site is served under
    /// another site's host, so the file would take a domain belonging to that one. `basePath` decides
    /// what counts as a path, so a bare trailing slash does not.
    public static func customDomain(from url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let host = URLComponents(string: withScheme)?.host, !host.isEmpty else { return nil }
        guard SiteBuilder.basePath(from: withScheme) == "/" else { return nil }
        return host.hasSuffix("github.io") ? nil : host
    }

    /// Publishes the contents of `distURL` to `branch` on `remote` (a URL or path) as a single
    /// force-pushed commit. Writes `CNAME` when a custom domain is given, plus `.nojekyll`.
    /// Branches that must never receive a force-pushed `dist/`. Publishing replaces the branch
    /// wholesale, so aiming it at a source branch would destroy real history.
    public static let alwaysProtectedBranches: Set<String> = ["main", "master", "trunk", "develop"]

    public func publish(
        distURL: URL,
        remote: String,
        branch: String = "gh-pages",
        cname: String? = nil,
        message: String = "Deploy site",
        alsoProtecting: Set<String> = []
    ) throws {
        let target = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else {
            throw GitError.failed("A publish branch is required.")
        }
        let protected = Self.alwaysProtectedBranches.union(alsoProtecting.map { $0.lowercased() })
        guard !protected.contains(target.lowercased()) else {
            throw GitError.failed(
                "Refusing to publish to \"\(target)\". Deploying force-pushes the built site and "
                + "would destroy the history on that branch. Use a publish branch such as gh-pages."
            )
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: distURL.path),
              let entries = try? fm.contentsOfDirectory(at: distURL, includingPropertiesForKeys: nil),
              !entries.isEmpty
        else { throw GitError.noDist }

        let temp = fm.temporaryDirectory.appendingPathComponent("op-deploy-\(UUID().uuidString)")
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }

        for item in entries {
            try fm.copyItem(at: item, to: temp.appendingPathComponent(item.lastPathComponent))
        }
        if let cname, !cname.isEmpty {
            try (cname + "\n").write(to: temp.appendingPathComponent("CNAME"), atomically: true, encoding: .utf8)
        }
        // Tell GitHub Pages to serve files as-is (no Jekyll processing).
        try Data().write(to: temp.appendingPathComponent(".nojekyll"))

        try run(["init", "-b", target], in: temp)
        try run(["add", "-A"], in: temp)
        try run(identityArgs + ["commit", "-m", message], in: temp)
        try run(["push", "--force", remote, "\(target):\(target)"], in: temp)
    }

    // MARK: Pending changes

    /// One file a commit would stage.
    struct PendingChange: Equatable, Sendable {
        var path: String
        var change: CommitPreview.File.Change
    }

    /// Reports what `commit` would stage, without modifying the site or its repository.
    func pendingChanges(siteURL: URL) throws -> [PendingChange] {
        let statusArgs = ["status", "--porcelain", "-z", "--untracked-files=all"]
        let gitignoreURL = siteURL.appendingPathComponent(".gitignore")
        let existing = (try? String(contentsOf: gitignoreURL, encoding: .utf8)) ?? ""
        let pendingIgnore = Self.gitignoreText(existing: existing)

        var result: [PendingChange]
        if isRepository(siteURL) {
            result = Self.parsePorcelainZ(try runRaw(statusArgs, in: siteURL))
        } else {
            // Commit would `git init` here first. Borrow an empty repository in the temp directory
            // so the scan writes nothing into the site, and name its git dir explicitly: a site
            // sitting inside another repository would otherwise make git walk up and report that
            // parent's changes. Seeding the probe's info/exclude with the .gitignore commit is
            // about to write leaves the exclusion rules to git rather than to a matcher of our own.
            let fm = FileManager.default
            let probe = fm.temporaryDirectory.appendingPathComponent("op-preview-\(UUID().uuidString)")
            try fm.createDirectory(at: probe, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: probe) }
            try run(["init", "-q"], in: probe)
            if let pendingIgnore {
                try pendingIgnore.write(to: probe.appendingPathComponent(".git/info/exclude"),
                                        atomically: true, encoding: .utf8)
            }
            let args = ["--git-dir", probe.appendingPathComponent(".git").path,
                        "--work-tree", siteURL.path] + statusArgs
            result = Self.parsePorcelainZ(try runRaw(args, in: siteURL))
        }

        // Commit writes .gitignore itself before staging, so the preview must not omit it. Guarded
        // because the scan already lists it when the file exists but is untracked or modified.
        if pendingIgnore != nil, !result.contains(where: { $0.path == ".gitignore" }) {
            let exists = FileManager.default.fileExists(atPath: gitignoreURL.path)
            result.append(PendingChange(path: ".gitignore", change: exists ? .modified : .added))
        }
        return result
    }

    /// Parses `git status --porcelain -z`. The NUL form is what makes this safe: paths are never
    /// C-quoted, so a name with a space survives. A rename carries a second field with the original
    /// path (new path first, the reverse of the human-readable form) that has to be consumed, or
    /// every following entry shifts by one.
    static func parsePorcelainZ(_ output: String) -> [PendingChange] {
        let fields = output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var result: [PendingChange] = []
        var index = 0
        while index < fields.count {
            let entry = fields[index]
            index += 1
            guard entry.count > 3 else { continue }
            let code = String(entry.prefix(2))
            if code.contains("R") || code.contains("C") { index += 1 }
            guard let change = Self.change(for: code) else { continue }
            result.append(PendingChange(path: String(entry.dropFirst(3)), change: change))
        }
        return result
    }

    private static func change(for code: String) -> CommitPreview.File.Change? {
        if code == "??" { return .added }
        // Added to the index and then deleted from the working tree: `add -A` drops it again, so
        // the commit would carry nothing for it.
        if code == "AD" { return nil }
        let letters = code.filter { $0 != " " }
        if letters.contains("R") || letters.contains("C") { return .renamed }
        if letters.contains("D") { return .deleted }
        if letters.contains("A") { return .added }
        return .modified
    }

    // MARK: Plumbing

    private var identityArgs: [String] {
        guard let author else { return [] }
        return ["-c", "user.name=\(author.name)", "-c", "user.email=\(author.email)"]
    }

    /// The `.gitignore` text `commit` would leave behind, or nil when the file already covers what
    /// Overprint manages. Shared with the commit preview so the preview cannot drift from the file
    /// commit actually writes.
    static func gitignoreText(existing: String) -> String? {
        guard !existing.contains("dist/") else { return nil }
        return existing.isEmpty ? "dist/\n.DS_Store\n" : existing + "\ndist/\n"
    }

    private func ensureGitignore(_ siteURL: URL) throws {
        let url = siteURL.appendingPathComponent(".gitignore")
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        guard let updated = Self.gitignoreText(existing: existing) else { return }
        try updated.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func gitBinary() -> String? {
        for path in ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"]
        where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    /// Runs a git command in `dir`, returning combined stdout+stderr on success or throwing
    /// `.failed` with the output on a non-zero exit.
    @discardableResult
    private func run(_ args: [String], in dir: URL) throws -> String {
        try runRaw(args, in: dir).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs git and returns its combined output untrimmed.
    ///
    /// `status --porcelain -z` output cannot be trimmed: an entry for an unstaged change begins
    /// with a space (" M content/posts/x.md"), so trimming shifts every path by one character.
    private func runRaw(_ args: [String], in dir: URL) throws -> String {
        guard let git = Self.gitBinary() else { throw GitError.gitNotFound }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: git)
        process.arguments = args
        process.currentDirectoryURL = dir

        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0" // never hang waiting for credentials
        let extraPath = ["/usr/bin", "/usr/local/bin", "/opt/homebrew/bin"]
        env["PATH"] = (extraPath + [env["PATH"] ?? ""]).joined(separator: ":")
        process.environment = env

        // Merge stderr into stdout: one pipe, drained fully, so no buffer deadlock.
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw GitError.failed("could not launch git: \(error.localizedDescription)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw GitError.failed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }
}
