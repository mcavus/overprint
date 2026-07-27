import Foundation
import OverprintKit

/// The structured plan the Build assistant returns as JSON. The app applies it deterministically
/// through OverprintKit (no assistant-written CSS or files), so it stays safe and reproducible.
struct SiteSpec: Codable, Equatable {
    /// Optional so a theme-only follow-up ({"theme":{...}}, the natural answer to "make the
    /// background cream") still decodes instead of failing the whole turn.
    var title: String?
    var author: String?
    var description: String?
    var theme: ThemeSpec?
    var posts: [PostSpec]?

    struct ThemeSpec: Codable, Equatable {
        var mode: String?
        var accent: String?
        var font: String?
        var background: String?
    }

    struct PostSpec: Codable, Equatable {
        var title: String
        var date: String?
        var tags: [String]?
        var body: String
    }

    /// Decodes tolerantly from the model's raw text, stripping any ```json fences or prose
    /// around the object. Returns nil if no valid JSON object is present.
    static func parse(_ raw: String) -> SiteSpec? {
        let cleaned = stripFences(raw)
        // Narrow to the outermost { … } in case the model added stray commentary.
        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}") else { return nil }
        let slice = String(cleaned[start...end])
        guard let data = slice.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SiteSpec.self, from: data)
    }

    private static func stripFences(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            // Drop the opening fence line (``` or ```json) and the trailing fence.
            if let firstNewline = t.firstIndex(of: "\n") {
                t = String(t[t.index(after: firstNewline)...])
            }
            if let fence = t.range(of: "```", options: .backwards) {
                t = String(t[..<fence.lowerBound])
            }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension SiteSpec {
    /// The site title the spec asks for, or nil when it did not supply one.
    var proposedTitle: String? {
        let name = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (name?.isEmpty == false) ? name : nil
    }

    /// Merges the spec's theme onto `existing`, field by field. A partial theme (say only a
    /// background) must not reset the accent or font the site already has.
    func mergedTheme(onto existing: SiteTheme?) -> SiteTheme? {
        guard let spec = theme else { return existing }
        var merged = existing ?? SiteTheme()
        if let mode = spec.mode.flatMap({ SiteTheme.Mode(rawValue: $0.lowercased()) }) { merged.mode = mode }
        if let font = spec.font.flatMap({ SiteTheme.Font(rawValue: $0.lowercased()) }) { merged.font = font }
        if let accent = spec.accent?.trimmingCharacters(in: .whitespacesAndNewlines), !accent.isEmpty {
            merged.accent = accent
        }
        if let background = spec.background?.trimmingCharacters(in: .whitespacesAndNewlines), !background.isEmpty {
            merged.background = background
        }
        return merged
    }

    /// Applies the spec onto the site's existing config, changing only what the spec supplied.
    /// Everything the assistant does not mention (notably `url` and `nav`) survives untouched.
    func applied(to existing: SiteConfig) -> SiteConfig {
        var config = existing
        if let proposedTitle { config.title = proposedTitle }
        if let author = author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
            config.author = author
        }
        if let description = description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            config.description = description
        }
        config.theme = mergedTheme(onto: existing.theme)
        return config
    }
}
