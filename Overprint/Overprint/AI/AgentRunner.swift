import Foundation
import OverprintKit

/// Turns a plain-language site description into a structured `SiteSpec` via Claude Code.
/// The system prompt constrains the model to emit JSON only; the app applies it deterministically
/// through OverprintKit. This is the Build assistant's single call to the model.
struct AgentRunner {
    /// A `--model` alias for the Claude Code CLI.
    var model = "opus"

    /// Optional long-lived subscription token (from `claude setup-token`).
    var oauthToken: String?

    /// A snapshot of the already-scaffolded site, passed on follow-up turns so the model
    /// re-themes or reconfigures without regenerating existing posts.
    struct CurrentSite {
        var title: String
        var author: String
        var description: String
        var mode: String
        var accent: String
        var font: String
        var postCount: Int
    }

    private func systemPrompt(hasPosts: Bool) -> String {
        let postsRule = hasPosts
            ? "This site already has posts. Do NOT include a \"posts\" array; only adjust title, author, description, and theme."
            : "Include a \"posts\" array with 2 or 3 short sample posts (2-4 short paragraphs of Markdown each) that fit the theme."
        return """
        You scaffold and theme a static Markdown blog. Read the user's description and return \
        ONLY a single JSON object, with no code fences, no preamble, and no commentary.

        The JSON shape is exactly:
        {
          "title": string,
          "author": string,
          "description": string,
          "theme": { "mode": "light" | "dark", "accent": "#rrggbb", "font": "serif" | "sans" | "mono", "background": "#rrggbb" },
          "posts": [ { "title": string, "date": "YYYY-MM-DD", "tags": [string], "body": string } ]
        }

        Rules:
        - "mode" is only "light" or "dark". "font" is only "serif", "sans", or "mono".
        - "accent" is a single hex color; it colors post titles and links, so pick something that \
        reads well against the background. For "add color" requests, choose a clear, non-grey accent.
        - "background" is the page color as a hex (e.g. "#F5EBDC" for cream). Set it whenever the \
        user asks about the background or page color. Keep text readable: use a light background with \
        "mode": "light", a dark background with "mode": "dark". Omit "background" to use the mode default.
        - "body" is Markdown only: no frontmatter and no surrounding code fences.
        - Use recent, plausible dates in YYYY-MM-DD form.
        - \(postsRule)
        - Do not add any keys beyond the shape above.
        """
    }

    private func userPrompt(description: String, current: CurrentSite?) -> String {
        guard let c = current else { return description }
        return """
        Current site:
        - title: \(c.title)
        - author: \(c.author)
        - description: \(c.description)
        - theme: mode=\(c.mode), accent=\(c.accent), font=\(c.font)
        - existing posts: \(c.postCount)

        Requested change:
        \(description)
        """
    }

    func generate(description: String, current: CurrentSite?) async throws -> SiteSpec {
        let hasPosts = (current?.postCount ?? 0) > 0
        let raw = try await ClaudeCodeClient(model: model, oauthToken: oauthToken).complete(
            system: systemPrompt(hasPosts: hasPosts),
            user: userPrompt(description: description, current: current)
        )
        guard let spec = SiteSpec.parse(raw) else {
            NSLog("Overprint: Build assistant returned unparseable output:\n\(raw)")
            throw ClaudeCodeError.failed("Claude didn't return a usable site plan. Try rephrasing your request.")
        }
        return spec
    }
}
