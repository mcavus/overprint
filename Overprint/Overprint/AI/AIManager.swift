import Foundation
import SwiftUI

/// The Claude model both AI lanes (inline copilot and Build assistant) use. Selectable in
/// Settings; defaults to Opus.
enum AIModel: String, CaseIterable, Identifiable {
    case opus48 = "claude-opus-4-8"
    case sonnet5 = "claude-sonnet-5"
    case haiku45 = "claude-haiku-4-5"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .opus48: return "Opus (most capable)"
        case .sonnet5: return "Sonnet (balanced)"
        case .haiku45: return "Haiku (fastest)"
        }
    }

    /// The alias passed to `claude --model`. Aliases track the latest model in each family.
    var cliAlias: String {
        switch self {
        case .opus48: return "opus"
        case .sonnet5: return "sonnet"
        case .haiku45: return "haiku"
        }
    }
}

/// Owns both AI lanes (inline copilot and Build assistant). Runs them through the local Claude
/// Code CLI, so usage draws from the user's Claude subscription with no API key. The app is
/// fully usable without Claude Code; the AI features simply stay disabled.
@MainActor
final class AIManager: ObservableObject {
    enum RequestState: Equatable {
        case idle
        case busy
        case done
        case error(String)
    }

    @Published private(set) var isAvailable = false
    @Published private(set) var hasToken = false
    @Published var state: RequestState = .idle
    @Published var selectedModel: AIModel {
        didSet { UserDefaults.standard.set(selectedModel.rawValue, forKey: Self.modelKey) }
    }

    private static let modelKey = "overprint.aiModel"
    private static let tokenAccount = "claude-oauth-token"

    /// The system prompt for the inline copilot's body rewrites.
    private static let copilotSystemPrompt = """
    You are a writing assistant embedded in a Markdown blog editor. The user gives an \
    instruction to revise the body of their post. Return only the revised Markdown body: \
    no frontmatter, no surrounding code fences, and no preamble or commentary. Preserve \
    the author's voice and existing Markdown formatting.
    """

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.modelKey)
        selectedModel = stored.flatMap(AIModel.init(rawValue:)) ?? .opus48
        refreshAvailability()
        hasToken = resolveToken() != nil
    }

    /// The long-lived token from `claude setup-token`: the Keychain first, then the
    /// CLAUDE_CODE_OAUTH_TOKEN environment variable. Nil falls back to the CLI's own login.
    private func resolveToken() -> String? {
        if let stored = Keychain.get(Self.tokenAccount), !stored.isEmpty { return stored }
        if let env = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"], !env.isEmpty { return env }
        return nil
    }

    /// Whether a token comes from the Keychain (vs the environment), for Settings copy.
    var tokenSource: String {
        if Keychain.get(Self.tokenAccount) != nil { return "Token saved in Keychain" }
        if ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"]?.isEmpty == false {
            return "Using CLAUDE_CODE_OAUTH_TOKEN"
        }
        return "No token saved (using Claude Code's own login)"
    }

    func setToken(_ value: String) {
        // Remove all whitespace/newlines: a copy from the wrapped `setup-token` output can carry
        // an interior line break, which makes an invalid Authorization header.
        let cleaned = value.components(separatedBy: .whitespacesAndNewlines).joined()
        if cleaned.isEmpty {
            Keychain.delete(Self.tokenAccount)
        } else {
            Keychain.set(cleaned, account: Self.tokenAccount)
        }
        hasToken = resolveToken() != nil
    }

    func clearToken() {
        Keychain.delete(Self.tokenAccount)
        hasToken = resolveToken() != nil
    }

    /// Where Claude Code was found, for Settings. Recomputed each read so it reflects a
    /// mid-session install.
    var status: String {
        if let path = ClaudeCodeClient.locateBinary() {
            return "Claude Code detected at \(path)"
        }
        return "Claude Code not found. Install it and sign in with your Claude subscription."
    }

    func refreshAvailability() { isAvailable = ClaudeCodeClient.isAvailable }

    func resetState() { state = .idle }

    private var cliModel: String { selectedModel.cliAlias }

    /// Runs a copilot edit. Returns the revised body on success (and sets `state`), or nil.
    func edit(instruction: String, body: String) async -> String? {
        refreshAvailability()
        guard isAvailable else {
            state = .error(ClaudeCodeError.notFound.errorDescription ?? "Claude Code not found.")
            return nil
        }
        state = .busy
        do {
            let userContent = "Instruction: \(instruction)\n\nCurrent post body:\n\n\(body)"
            let result = try await ClaudeCodeClient(model: cliModel, oauthToken: resolveToken())
                .complete(system: Self.copilotSystemPrompt, user: userContent)
            state = .done
            return result
        } catch {
            state = .error(error.localizedDescription)
            return nil
        }
    }

    /// Runs the open-ended site agent: Claude Code works directly in the site folder.
    /// Returns its summary on success, or nil on failure (with `state` set).
    func runAgent(prompt: String, site: URL) async -> SiteAgent.Outcome? {
        refreshAvailability()
        guard isAvailable else {
            state = .error(ClaudeCodeError.notFound.errorDescription ?? "Claude Code not found.")
            return nil
        }
        state = .busy
        do {
            let outcome = try await SiteAgent(model: cliModel, oauthToken: resolveToken())
                .run(prompt: prompt, site: site)
            state = .done
            return outcome
        } catch {
            state = .error(error.localizedDescription)
            return nil
        }
    }

    /// Runs the Build assistant: turns a description into a structured `SiteSpec`. Returns the
    /// spec on success (and sets `state`), or nil on failure.
    func generateSite(description: String, current: AgentRunner.CurrentSite?) async -> SiteSpec? {
        refreshAvailability()
        guard isAvailable else {
            state = .error(ClaudeCodeError.notFound.errorDescription ?? "Claude Code not found.")
            return nil
        }
        state = .busy
        do {
            let spec = try await AgentRunner(model: cliModel, oauthToken: resolveToken()).generate(description: description, current: current)
            state = .done
            return spec
        } catch {
            state = .error(error.localizedDescription)
            return nil
        }
    }
}
