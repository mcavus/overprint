import Foundation

/// Turns a `SiteTheme` into the small pieces the templates inject: a `:root` variable
/// override and an optional web-font link. The base stylesheet stays fixed; only these
/// CSS variables change per site.
enum ThemeCSS {
    static func tokens(_ theme: SiteTheme) -> [String: String] {
        ["rootStyle": rootStyle(theme), "fontLink": fontLink(theme.font)]
    }

    static func rootStyle(_ theme: SiteTheme) -> String {
        var vars: [String] = [
            "--accent: \(safeHex(theme.accent));",
            "--display: \(fontFamily(theme.font));",
        ]
        if theme.mode == .dark {
            vars.append(contentsOf: [
                "--paper: #14141b;",
                "--ink: #f3f3f5;",
                "--body: #c9c9d2;",
                "--muted: #9a9aa6;",
                "--faint: #7c7c88;",
                "--rule: rgba(255,255,255,0.16);",
                "--rule-soft: rgba(255,255,255,0.10);",
                "--code-bg: #24242e;",
            ])
        }
        // An explicit background overrides the mode's default paper (comes last so it wins).
        if let background = theme.background, let hex = validHex(background) {
            vars.append("--paper: \(hex);")
        }
        return "<style>:root{ \(vars.joined(separator: " ")) }</style>"
    }

    static func fontLink(_ font: SiteTheme.Font) -> String {
        // Serif (Source Serif 4) and mono (JetBrains Mono) are already linked in base.html.
        switch font {
        case .sans:
            return "<link href=\"https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap\" rel=\"stylesheet\">"
        case .serif, .mono:
            return ""
        }
    }

    static func fontFamily(_ font: SiteTheme.Font) -> String {
        switch font {
        case .serif: return "\"Source Serif 4\", Georgia, \"Times New Roman\", serif"
        case .sans: return "\"Inter\", -apple-system, BlinkMacSystemFont, \"Helvetica Neue\", Arial, sans-serif"
        case .mono: return "\"JetBrains Mono\", ui-monospace, \"SF Mono\", Menlo, monospace"
        }
    }

    /// Returns `value` if it is a `#rgb` / `#rrggbb` hex color, otherwise nil.
    static func validHex(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let body = trimmed.dropFirst()
        let valid = trimmed.hasPrefix("#")
            && (trimmed.count == 4 || trimmed.count == 7)
            && body.allSatisfy(\.isHexDigit)
        return valid ? trimmed : nil
    }

    /// Accepts `#rgb` / `#rrggbb`; falls back to the default accent otherwise.
    static func safeHex(_ value: String) -> String {
        validHex(value) ?? "#0A7AFF"
    }
}
