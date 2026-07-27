import Foundation

/// The default theme, loaded from bundled resources under `Resources/Theme`. Holds the
/// Stencil templates (keyed by name for a `DictionaryLoader`) and the stylesheet.
struct Theme {
    let templates: [String: String]
    let styleCSS: String

    static func bundled() throws -> Theme {
        guard let themeRoot = Bundle.module.resourceURL?.appendingPathComponent("Theme") else {
            throw OverprintError.templateError("bundled theme resources are missing")
        }
        let templatesDir = themeRoot.appendingPathComponent("templates")

        func read(_ url: URL) throws -> String {
            do {
                return try String(contentsOf: url, encoding: .utf8)
            } catch {
                throw OverprintError.templateError("could not read \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        let base = try read(templatesDir.appendingPathComponent("base.html"))
        let index = try read(templatesDir.appendingPathComponent("index.html"))
        let post = try read(templatesDir.appendingPathComponent("post.html"))
        let tag = try read(templatesDir.appendingPathComponent("tag.html"))
        let page = try read(templatesDir.appendingPathComponent("page.html"))
        let nav = try read(templatesDir.appendingPathComponent("nav.html"))
        let css = try read(themeRoot.appendingPathComponent("assets/style.css"))

        return Theme(
            templates: [
                "base.html": base,
                "index.html": index,
                "post.html": post,
                "tag.html": tag,
                "page.html": page,
                "nav.html": nav,
            ],
            styleCSS: css
        )
    }
}
