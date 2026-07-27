import Foundation
import SwiftUI
import OverprintKit

/// Owns Commit and Deploy for the current site, wrapping OverprintKit's `GitDeploy`.
///
/// A site is connected to GitHub once: the repository is stored as the git `origin` remote and the
/// published URL in `overprint.yml`. Both persist with the site, so after that first setup Commit
/// and Deploy never ask for an address again. All git work runs off the main thread; commits use
/// the machine's global git identity.
@MainActor
final class GitManager: ObservableObject {
    static let publishBranch = "gh-pages"

    enum Phase: Equatable {
        case idle
        case working
        case done
        case error(String)
    }

    struct Step: Identifiable, Equatable {
        enum Status { case pending, active, done, failed }
        let id = UUID()
        var label: String
        var status: Status
    }

    /// What Overprint remembers about where a site publishes.
    struct Connection: Equatable {
        var isRepository = false
        var hasChanges = false
        var branch: String?
        /// The GitHub repository (git `origin`), or nil when the site is not connected yet.
        var repository: String?
        /// The published site URL, from `overprint.yml`.
        var url: String?

        var isConnected: Bool { repository?.isEmpty == false }
    }

    @Published private(set) var connection = Connection()
    @Published var commitPhase: Phase = .idle
    @Published var deployPhase: Phase = .idle
    @Published private(set) var deploySteps: [Step] = []

    // MARK: Status

    func refresh(site: URL) async {
        connection = await Self.compute {
            let git = GitDeploy()
            let status = git.status(siteURL: site)
            let url = (try? SiteStore(siteURL: site).loadConfig().url) ?? nil
            return Connection(
                isRepository: status.isRepository,
                hasChanges: status.hasChanges,
                branch: status.branch,
                repository: status.remoteURL,
                url: url
            )
        }
    }

    // MARK: Connect (one-time per site)

    /// Sets the repository as `origin` and writes the URL into `overprint.yml`, so Commit and Deploy
    /// can use them without asking again. Returns an error message, or nil on success.
    func connect(site: URL, repository: String, url: String) async -> String? {
        let repo = repository.trimmingCharacters(in: .whitespacesAndNewlines)
        let siteURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repo.isEmpty else { return "Enter the GitHub repository." }

        do {
            try await Self.run {
                let git = GitDeploy()
                try git.initializeIfNeeded(siteURL: site)
                try git.setRemote(siteURL: site, url: repo)

                var config = (try? SiteStore(siteURL: site).loadConfig()) ?? SiteConfig()
                config.url = siteURL.isEmpty ? nil : siteURL
                try config.save(to: site.appendingPathComponent("overprint.yml"))
            }
            await refresh(site: site)
            return nil
        } catch {
            return Self.message(error)
        }
    }

    // MARK: Commit

    /// Commits the source and, when the site is connected, pushes it to `origin`. No repository to
    /// enter: it uses the one the site remembers.
    func commit(site: URL, message: String) async {
        commitPhase = .working
        let connected = connection.isConnected

        var committed = false
        do {
            try await Self.run { try GitDeploy().commit(siteURL: site, message: message) }
            committed = true
        } catch let error as GitDeploy.GitError {
            // "Nothing to commit" is only a problem when there is also nothing to push.
            if case .nothingToCommit = error, connected {
                committed = false
            } else {
                commitPhase = .error(Self.message(error))
                return
            }
        } catch {
            commitPhase = .error(Self.message(error))
            return
        }

        guard connected else {
            commitPhase = .done
            await refresh(site: site)
            return
        }

        do {
            try await Self.run { try GitDeploy().pushSource(siteURL: site) }
            commitPhase = .done
        } catch {
            let prefix = committed ? "Committed locally, but the push failed: " : "Push failed: "
            commitPhase = .error(prefix + Self.message(error))
        }
        await refresh(site: site)
    }

    func resetCommit() { commitPhase = .idle }

    // MARK: Deploy

    /// Builds and publishes the site to its remembered repository. No fields to fill in.
    func deploy(site: URL) async {
        deployPhase = .working

        let info = await Self.compute { () -> (remote: String?, url: String, sourceBranch: String?) in
            let git = GitDeploy()
            let status = git.status(siteURL: site)
            let url = ((try? SiteStore(siteURL: site).loadConfig().url) ?? nil) ?? ""
            let source = (status.isRepository && git.hasCommits(site)) ? status.branch : nil
            return (status.remoteURL, url, source)
        }

        guard let remote = info.remote, !remote.isEmpty else {
            deployPhase = .error("Connect this site to a GitHub repository first.")
            return
        }

        let branch = Self.publishBranch
        var steps = [Step(label: "Building site", status: .active)]
        if let source = info.sourceBranch { steps.append(Step(label: "Pushing source to \(source)", status: .pending)) }
        steps.append(Step(label: "Publishing to \(branch)", status: .pending))
        steps.append(Step(label: "Published", status: .pending))
        deploySteps = steps

        let sourceIndex = 1
        let publishIndex = info.sourceBranch != nil ? 2 : 1
        let doneIndex = publishIndex + 1

        do {
            try await Self.run { try SiteBuilder().build(siteURL: site, includeDrafts: false) }
            setStep(0, .done)

            if info.sourceBranch != nil {
                setStep(sourceIndex, .active)
                try await Self.run { try GitDeploy().pushSource(siteURL: site) }
                setStep(sourceIndex, .done)
            }
            setStep(publishIndex, .active)

            let cname = Self.customDomain(from: info.url)
            let dist = site.appendingPathComponent("dist")
            let protectedSource = Set([info.sourceBranch].compactMap { $0?.lowercased() })
            try await Self.run {
                try GitDeploy().publish(
                    distURL: dist,
                    remote: remote,
                    branch: branch,
                    cname: cname,
                    alsoProtecting: protectedSource
                )
            }
            setStep(publishIndex, .done)
            setStep(doneIndex, .done)
            deployPhase = .done
            await refresh(site: site)
        } catch {
            if let index = deploySteps.firstIndex(where: { $0.status == .active }) {
                deploySteps[index].status = .failed
            }
            deployPhase = .error(Self.message(error))
        }
    }

    func resetDeploy() {
        deployPhase = .idle
        deploySteps = []
    }

    private func setStep(_ index: Int, _ status: Step.Status) {
        guard deploySteps.indices.contains(index) else { return }
        deploySteps[index].status = status
    }

    // MARK: Helpers

    /// The host of `url` when it is a custom domain (not a github.io page), for the CNAME file.
    static func customDomain(from url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let host = URLComponents(string: withScheme)?.host, !host.isEmpty else { return nil }
        return host.hasSuffix("github.io") ? nil : host
    }

    private static func message(_ error: Error) -> String {
        let base = (error as? GitDeploy.GitError)?.errorDescription ?? error.localizedDescription
        let lowered = base.lowercased()
        // "Repository not found" and permission errors almost always mean git is authenticated as a
        // different GitHub account than the repo's owner, which reads like an app bug otherwise.
        let looksLikeAuth = lowered.contains("repository not found")
            || lowered.contains("could not read username")
            || lowered.contains("could not read password")
            || lowered.contains("permission denied")
            || lowered.contains("authentication failed")
            || lowered.contains("403")
        guard looksLikeAuth else { return base }
        return base
            + "\n\nIf this repository exists and you can open it in a browser, your Mac's git is "
            + "probably signed in as a different GitHub account than the one that owns it. Check with "
            + "`gh auth status`, and make sure the repository URL matches that account."
    }

    private static func run(_ work: @Sendable @escaping () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do { try work(); continuation.resume() }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private static func compute<T: Sendable>(_ work: @Sendable @escaping () -> T) async -> T {
        await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: work())
            }
        }
    }
}
