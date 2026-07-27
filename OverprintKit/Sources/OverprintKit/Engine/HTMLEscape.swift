import Foundation

/// Escapes text for safe interpolation into HTML.
///
/// Stencil does not autoescape and ships no `escape` filter, so values are escaped where the
/// template contexts are built rather than at each interpolation site. That keeps the rule in one
/// place instead of depending on every template author remembering a filter.
///
/// Rendered Markdown (`content_html`) and the generated theme tags are deliberately NOT escaped:
/// they are HTML by construction.
enum HTMLEscape {
    static func escape(_ string: String) -> String {
        var out = string.replacingOccurrences(of: "&", with: "&amp;") // must come first
        out = out.replacingOccurrences(of: "<", with: "&lt;")
        out = out.replacingOccurrences(of: ">", with: "&gt;")
        out = out.replacingOccurrences(of: "\"", with: "&quot;")
        // &#39; rather than &apos;, which is not defined in HTML 4.
        out = out.replacingOccurrences(of: "'", with: "&#39;")
        return out
    }

    static func escape(_ strings: [String]) -> [String] {
        strings.map(escape)
    }
}
