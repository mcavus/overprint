import Foundation
import OverprintKit

/// Runs Claude Code as a real agent inside the site folder, with its file tools enabled.
///
/// This is the open-ended counterpart to `AgentRunner`. `AgentRunner` asks for a JSON spec and the
/// app applies it, which is safe and reproducible but can only express what the spec has fields
/// for. `SiteAgent` hands the folder over and lets Claude edit the Markdown and config directly,
/// which is what makes requests like "add an about page" or "rewrite my last post" possible.
///
/// The safety story is git, not restriction: `BuildModel` commits before each run, so any turn can
/// be undone, and validates afterwards so a broken site is reported rather than silently served.
struct SiteAgent {
    /// A `--model` alias for the Claude Code CLI.
    var model = "opus"
    /// Optional long-lived subscription token (from `claude setup-token`).
    var oauthToken: String?

    struct Outcome {
        /// The assistant's closing summary of what it did.
        var summary: String
        /// Turn count, useful for showing that real work happened.
        var turns: Int
    }

    private func systemPrompt(site: URL) -> String {
        """
        You are working inside an Overprint site, a static blog built from Markdown files. The \
        folder is the single source of truth. Make the change the user asks for by editing files \
        directly, then stop.

        Layout:
        - `overprint.yml` at the root is the site config: title, author, description, url, a \
        `theme` block (mode light|dark, accent hex, font serif|sans|mono, background hex), and an \
        optional `nav` list of { label, url } entries.
        - `content/posts/YYYY-MM-DD-slug.md` is one post per file.
        - `content/pages/<slug>.md` is one standalone page per file.
        - `dist/` is GENERATED output. Never edit it, never read it as truth, never commit it. It \
        is deleted and rewritten on every build.

        Post frontmatter is a frozen contract. Every post has exactly these fields:
        ```
        ---
        title: <string>
        date: <YYYY-MM-DD>
        tags: [<string>, ...]
        slug: <string>
        draft: <true|false>
        ---
        ```
        Pages use only `title`, plus optional `slug` and `draft`. Pages have no date and no tags.

        Rules:
        - Never rename, drop, or invent frontmatter fields.
        - Keep the filename date prefix in sync with the `date` field, and the filename slug in \
        sync with the `slug` field.
        - Slugs must be unique across all posts and pages, because each becomes `<slug>.html`.
        - A page slugged `index`, `feed`, `sitemap`, or `tag-<something>` would collide with \
        generated output. Do not use those.
        - `nav` entries may only point at pages that will exist: `index.html`, a page slug, or a \
        tag page for a tag that a published post actually carries.
        - Do not write em dashes in any prose you author.
        - Do not mention Claude or AI anywhere in the site's content.
        - Stay inside this folder. Do not touch anything elsewhere on the machine.

        Work only within the site at \(site.path). When you are done, reply with a short plain \
        summary of what you changed, in one or two sentences. Do not include code fences.
        """
    }

    func run(prompt: String, site: URL) async throws -> Outcome {
        guard let binary = ClaudeCodeClient.locateBinary() else { throw ClaudeCodeError.notFound }
        let model = self.model
        let token = self.oauthToken
        let system = systemPrompt(site: site)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let outcome = try Self.runBlocking(
                        binary: binary, model: model, token: token,
                        system: system, prompt: prompt, site: site
                    )
                    continuation.resume(returning: outcome)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runBlocking(
        binary: String, model: String, token: String?,
        system: String, prompt: String, site: URL
    ) throws -> Outcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        // Tools are ENABLED here, unlike the spec path. `acceptEdits` lets it write without an
        // interactive approval prompt, which would simply hang in a headless run. `--add-dir`
        // scopes it to the site so it cannot wander into the rest of the disk.
        process.arguments = [
            "-p",
            "--output-format", "json",
            "--model", model,
            "--append-system-prompt", system,
            "--permission-mode", "acceptEdits",
            "--add-dir", site.path,
        ]

        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "ANTHROPIC_API_KEY")
        env.removeValue(forKey: "ANTHROPIC_AUTH_TOKEN")
        if let token {
            let cleaned = token.components(separatedBy: .whitespacesAndNewlines).joined()
            if !cleaned.isEmpty { env["CLAUDE_CODE_OAUTH_TOKEN"] = cleaned }
        }
        // Must match ClaudeCodeClient's PATH: it searches ~/.claude/local and ~/.local/bin for the
        // binary, so omitting them here can launch a claude whose own directory is off its PATH.
        let home = NSHomeDirectory()
        let extra = [
            "/opt/homebrew/bin", "/usr/local/bin",
            "\(home)/.claude/local", "\(home)/.local/bin",
            "/usr/bin", "/bin",
        ]
        env["PATH"] = (extra + [env["PATH"] ?? ""]).joined(separator: ":")
        process.environment = env
        // Running in the site folder is what makes relative paths mean what the model expects.
        process.currentDirectoryURL = site

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
        if let data = prompt.data(using: .utf8) {
            inPipe.fileHandleForWriting.write(data)
        }
        inPipe.fileHandleForWriting.closeFile()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let json = try? JSONSerialization.jsonObject(with: outData) as? [String: Any] else {
            NSLog("Overprint: agent produced no JSON (exit %d)", process.terminationStatus)
            throw ClaudeCodeError.empty
        }
        let result = (json["result"] as? String) ?? ""
        if (json["is_error"] as? Bool) == true {
            let status = json["api_error_status"] as? Int
            let lowered = result.lowercased()
            if status == 401 || lowered.contains("oauth") || lowered.contains("authenticate") {
                throw ClaudeCodeError.notAuthenticated
            }
            throw ClaudeCodeError.failed(result.isEmpty ? "Claude Code reported an error." : result)
        }

        let summary = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return Outcome(
            summary: summary.isEmpty ? "Done." : summary,
            turns: (json["num_turns"] as? Int) ?? 1
        )
    }
}
