import Foundation
import SwiftUI
import OverprintKit

/// Drives Build mode: turns a description into a `SiteSpec` via the assistant, then applies it
/// deterministically through OverprintKit (scaffold → posts → theme → build & serve) while
/// animating the step rows. Keeps a running transcript of turns so follow-ups accumulate as a
/// conversation. One instance per open site; shares the server and AI manager.
@MainActor
final class BuildModel: ObservableObject {
    struct Step: Identifiable {
        enum Status { case pending, active, done, failed }
        let id = UUID()
        var label: String
        var detail: String
        var status: Status
    }

    /// One exchange: the user's prompt and the assistant's streamed response.
    struct Turn: Identifiable {
        /// Which lane ran: the deterministic first-run scaffold, or the open-ended agent.
        enum Kind { case scaffold, change }

        let id = UUID()
        var prompt: String
        var steps: [Step]
        var kind: Kind = .scaffold
        var isDone = false
        var errorMessage: String?
        var servedPort: Int?
        /// The agent's own description of what it changed, for open-ended turns.
        var summary: String?
    }

    let site: URL

    @Published private(set) var turns: [Turn] = []
    @Published var composer: String = ""
    @Published private(set) var reloadToken = 0
    @Published private(set) var isRunning = false

    private let serverManager: ServerManager
    private let ai: AIManager

    init(site: URL, serverManager: ServerManager, ai: AIManager) {
        self.site = site
        self.serverManager = serverManager
        self.ai = ai
    }

    var hasStarted: Bool { !turns.isEmpty }

    /// The index page of the served site, or nil when the server is stopped.
    var previewURL: URL? {
        guard serverManager.isServing, let base = serverManager.url else { return nil }
        return base.appendingPathComponent("index.html")
    }

    /// Bumped by the file watcher so the shared preview reloads on external changes.
    func bumpPreview() { reloadToken += 1 }

    // MARK: Composing

    func send() {
        let text = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRunning else { return }
        composer = ""
        // A brand new site has no content to edit, so the first turn always scaffolds. After that
        // the agent can do anything, which is the whole point of chatting with it.
        let hasContent = ((try? SiteStore(siteURL: site).loadPosts().count) ?? 0) > 0
        Task { hasContent ? await runAgent(prompt: text) : await run(prompt: text) }
    }

    func useSuggestion(_ text: String) {
        guard !isRunning else { return }
        Task { await run(prompt: text) }
    }

    // MARK: Open-ended agent

    /// Hands the site folder to Claude Code with its file tools enabled, so it can make changes
    /// the structured spec cannot express.
    ///
    /// Guarded by git rather than by restriction: see `SiteAgent`. Commits before the turn,
    /// validates after, and refuses to serve a site that no longer validates.
    private func runAgent(prompt: String) async {
        isRunning = true
        let index = turns.count
        turns.append(Turn(prompt: prompt, steps: Self.agentSteps(), kind: .change))

        // 1. Snapshot, so the change can always be undone.
        await step(index, 0) {
            do {
                try GitDeploy().commit(siteURL: self.site, message: "Before: \(prompt.prefix(60))")
                return "snapshot"
            } catch let error as GitDeploy.GitError {
                // A clean tree means there is nothing to snapshot, which is fine.
                if case .nothingToCommit = error { return "already clean" }
                throw error
            }
        }

        // 2. Let the agent work.
        var summary = ""
        await step(index, 1) {
            guard let outcome = await self.ai.runAgent(prompt: prompt, site: self.site) else {
                if case .error(let message) = self.ai.state { throw AgentFailure.message(message) }
                throw AgentFailure.message("The assistant could not complete that.")
            }
            summary = outcome.summary
            return outcome.turns == 1 ? "1 step" : "\(outcome.turns) steps"
        }

        // 3. Check what it produced before serving it.
        await step(index, 2) {
            let issues = SiteStore(siteURL: self.site).validate()
            guard issues.isEmpty else {
                throw AgentFailure.message(
                    "The site no longer validates, so nothing was published. "
                    + issues.map(\.description).joined(separator: "; ")
                    + " Your previous version is safe in git."
                )
            }
            return "valid"
        }

        // 4. Rebuild and reload the preview.
        await step(index, 3) {
            try SiteBuilder().build(siteURL: self.site, includeDrafts: true)
            if !self.serverManager.isServing { self.serverManager.start(dist: self.site.appendingPathComponent("dist")) }
            self.reloadToken += 1
            return "localhost:\(self.serverManager.port)"
        }

        turns[index].servedPort = serverManager.isServing ? serverManager.port : nil
        turns[index].summary = summary.isEmpty ? nil : summary
        turns[index].isDone = true
        isRunning = false
    }

    private enum AgentFailure: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self { case .message(let text): return text }
        }
    }

    private static func agentSteps() -> [Step] {
        [
            Step(label: "Saving a snapshot", detail: "", status: .pending),
            Step(label: "Making the changes", detail: "", status: .pending),
            Step(label: "Checking the site", detail: "", status: .pending),
            Step(label: "Rebuilding and serving", detail: "", status: .pending),
        ]
    }

    // MARK: Run

    private func run(prompt: String) async {
        isRunning = true
        let index = turns.count
        turns.append(Turn(prompt: prompt, steps: []))

        let existingPosts = (try? SiteStore(siteURL: site).loadPosts().count) ?? 0
        let current = existingPosts > 0 ? currentContext(postCount: existingPosts) : nil

        guard let spec = await ai.generateSite(description: prompt, current: current) else {
            if case .error(let message) = ai.state { turns[index].errorMessage = message }
            turns[index].isDone = true
            isRunning = false
            return
        }

        // Now that we have a plan, reveal the step rows and apply it.
        turns[index].steps = Self.freshSteps()
        let existingConfig = (try? SiteStore(siteURL: site).loadConfig()) ?? SiteConfig()
        let scaffoldTitle = spec.proposedTitle
            ?? (existingConfig.title.isEmpty ? site.lastPathComponent : existingConfig.title)

        await step(index, 0) { try SiteScaffolder().scaffold(at: self.site, title: scaffoldTitle); return "content · posts" }
        await step(index, 1) {
            if existingPosts > 0 { return "kept \(existingPosts)" }
            let count = try self.writePosts(spec)
            return count == 1 ? "1 file" : "\(count) files"
        }
        await step(index, 2) {
            // Merge onto the config on disk. A theme-only turn must not drop url: or nav:.
            let current = (try? SiteStore(siteURL: self.site).loadConfig()) ?? existingConfig
            let config = spec.applied(to: current)
            try config.save(to: self.site.appendingPathComponent("overprint.yml"))
            let theme = config.theme ?? SiteTheme()
            var detail = "\(theme.mode.rawValue) · \(theme.accent)"
            if let background = theme.background { detail += " · \(background)" }
            return detail
        }
        await step(index, 3) {
            try SiteBuilder().build(siteURL: self.site, includeDrafts: true)
            if !self.serverManager.isServing { self.serverManager.start(dist: self.site.appendingPathComponent("dist")) }
            self.reloadToken += 1
            return "localhost:\(self.serverManager.port)"
        }

        turns[index].servedPort = serverManager.isServing ? serverManager.port : nil
        turns[index].isDone = true
        isRunning = false
    }

    /// Marks a step active, waits a beat, runs its work, and records the result detail (or the
    /// failure). Skips remaining steps once one in this turn has failed.
    private func step(_ turn: Int, _ index: Int, _ work: @escaping () async throws -> String) async {
        guard turns[turn].errorMessage == nil else { return }
        turns[turn].steps[index].status = .active
        try? await Task.sleep(nanoseconds: 240_000_000)
        do {
            let detail = try await work()
            turns[turn].steps[index].detail = detail
            turns[turn].steps[index].status = .done
        } catch {
            turns[turn].steps[index].status = .failed
            turns[turn].errorMessage = (error as? OverprintError)?.description ?? error.localizedDescription
        }
        try? await Task.sleep(nanoseconds: 130_000_000)
    }

    /// Writes the spec's sample posts to `content/posts` and returns how many were written.
    private func writePosts(_ spec: SiteSpec) throws -> Int {
        let writer = PostWriter()
        let posts = spec.posts ?? []
        for post in posts {
            try writer.createPost(
                in: site,
                title: post.title,
                date: Self.parseDate(post.date) ?? Date(),
                body: post.body,
                tags: post.tags ?? [],
                draft: false
            )
        }
        return posts.count
    }

    private func currentContext(postCount: Int) -> AgentRunner.CurrentSite {
        let config = (try? SiteStore(siteURL: site).loadConfig()) ?? SiteConfig()
        let theme = config.theme ?? SiteTheme()
        return AgentRunner.CurrentSite(
            title: config.title,
            author: config.author,
            description: config.description,
            mode: theme.mode.rawValue,
            accent: theme.accent,
            font: theme.font.rawValue,
            postCount: postCount
        )
    }

    private static func freshSteps() -> [Step] {
        [
            Step(label: "Creating project structure", detail: "", status: .pending),
            Step(label: "Generating posts", detail: "", status: .pending),
            Step(label: "Applying theme", detail: "", status: .pending),
            Step(label: "Building and serving", detail: "", status: .pending),
        ]
    }

    private static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: string)
    }
}
