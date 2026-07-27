import Foundation

/// Errors from invoking the local Claude Code CLI.
enum ClaudeCodeError: Error, LocalizedError {
    case notFound
    case notAuthenticated
    case failed(String)
    case empty
    case launch(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Claude Code was not found. Install it and sign in with your Claude subscription."
        case .notAuthenticated:
            return "Claude Code isn't authenticated. Run claude setup-token in a terminal, then paste the token in Settings."
        case .failed(let message):
            return message
        case .empty:
            return "Claude Code returned an empty response."
        case .launch(let reason):
            return "Couldn't launch Claude Code: \(reason)"
        }
    }
}

/// Runs the local `claude` CLI headlessly (`claude -p … --output-format json`) so Overprint's
/// AI draws from the user's Claude subscription. There is no API key: the CLI uses its own
/// OAuth login. Built-in tools are disabled, so the model only returns text; the app applies
/// any changes itself.
struct ClaudeCodeClient {
    /// A `--model` alias ("opus", "sonnet", "haiku") or a full model id.
    var model: String

    /// A long-lived subscription token from `claude setup-token`, passed as
    /// `CLAUDE_CODE_OAUTH_TOKEN` so headless runs authenticate reliably. Optional: without it,
    /// the CLI falls back to its own keychain login (which may be expired for headless use).
    var oauthToken: String?

    /// Common install locations, tried before falling back to a login-shell lookup.
    private static var candidatePaths: [String] {
        [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(NSHomeDirectory())/.claude/local/claude",
            "\(NSHomeDirectory())/.local/bin/claude",
        ]
    }

    /// Directories a GUI app (launched from Finder with a bare PATH) should add so `claude`
    /// and anything it shells out to resolve.
    private static var extraPathDirs: [String] {
        [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(NSHomeDirectory())/.claude/local",
            "\(NSHomeDirectory())/.local/bin",
            "/usr/bin",
            "/bin",
        ]
    }

    /// The resolved path to the `claude` binary, or nil if it isn't installed.
    static func locateBinary() -> String? {
        for path in candidatePaths where FileManager.default.fileExists(atPath: path) {
            return path
        }
        return loginShellWhich()
    }

    static var isAvailable: Bool { locateBinary() != nil }

    /// Asks the user's login shell where `claude` is, so non-standard installs (nvm, asdf,
    /// custom PATH) still resolve. GUI apps don't inherit the shell PATH otherwise.
    private static func loginShellWhich() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", "command -v claude"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n").last
        return (path?.isEmpty == false) ? path : nil
    }

    /// A one-shot completion: sends `system` + `user` and returns the model's text result.
    func complete(system: String, user: String) async throws -> String {
        guard let binary = Self.locateBinary() else { throw ClaudeCodeError.notFound }
        let model = self.model
        let token = self.oauthToken
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let text = try Self.runBlocking(binary: binary, model: model, token: token, system: system, user: user)
                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runBlocking(binary: String, model: String, token: String?, system: String, user: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        // `--system-prompt` replaces Claude Code's coding-agent prompt (so it just answers),
        // `--tools ""` disables all built-in tools, and the prompt goes over stdin so a variadic
        // flag can't swallow it.
        process.arguments = [
            "-p",
            "--output-format", "json",
            "--model", model,
            "--system-prompt", system,
            "--tools", "",
        ]

        // Use the subscription login. Drop API-billing credentials so the CLI never bills the
        // metered API, but keep any CLAUDE_CODE_OAUTH_TOKEN (that is subscription auth). Augment
        // PATH because a GUI app launched from Finder has only a bare PATH.
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "ANTHROPIC_API_KEY")
        env.removeValue(forKey: "ANTHROPIC_AUTH_TOKEN")
        if let token {
            let cleaned = token.components(separatedBy: .whitespacesAndNewlines).joined()
            if !cleaned.isEmpty { env["CLAUDE_CODE_OAUTH_TOKEN"] = cleaned }
        }
        let existingPath = env["PATH"] ?? ""
        env["PATH"] = (extraPathDirs + [existingPath]).joined(separator: ":")
        process.environment = env
        process.currentDirectoryURL = FileManager.default.temporaryDirectory

        let inPipe = Pipe()
        let outPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw ClaudeCodeError.launch(error.localizedDescription)
        }

        // Feed the prompt over stdin, then close it so the CLI proceeds.
        if let data = user.data(using: .utf8) {
            inPipe.fileHandleForWriting.write(data)
        }
        inPipe.fileHandleForWriting.closeFile()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let rawOutput = String(data: outData, encoding: .utf8) ?? ""
        NSLog("Overprint: claude (%@) exited %d, %d bytes stdout", binary, process.terminationStatus, outData.count)

        guard let json = jsonObject(from: outData) else {
            NSLog("Overprint: claude produced no JSON. Raw output:\n%@", rawOutput)
            throw ClaudeCodeError.empty
        }
        let result = (json["result"] as? String) ?? ""
        if (json["is_error"] as? Bool) == true {
            let status = json["api_error_status"] as? Int
            let lowered = result.lowercased()
            NSLog("Overprint: claude reported an error (status %@): %@", String(describing: status), result)
            if status == 401 || lowered.contains("oauth") || lowered.contains("authenticate") {
                throw ClaudeCodeError.notAuthenticated
            }
            throw ClaudeCodeError.failed(result.isEmpty ? "Claude Code reported an error." : result)
        }
        let text = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ClaudeCodeError.empty }
        return text
    }

    /// Parses the CLI's JSON, tolerating a noisy line or two (e.g. a shell profile echo) by
    /// scanning stdout lines for the result object.
    private static func jsonObject(from data: Data) -> [String: Any]? {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return obj }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: "\n").reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{"), let lineData = trimmed.data(using: .utf8) else { continue }
            if let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] { return obj }
        }
        return nil
    }
}
