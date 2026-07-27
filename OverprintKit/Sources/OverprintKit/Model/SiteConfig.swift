import Foundation
import Yams

/// Site-level configuration loaded from `overprint.yml` at the site root, the single
/// source of truth. Every field is optional with a sensible default so a minimal config
/// still loads.
/// One entry in the site's header navigation. `url` is a page name in the built output
/// (for example `about.html` or `tag-notes.html`), or any absolute URL.
public struct NavItem: Codable, Equatable, Sendable {
    public var label: String
    public var url: String

    public init(label: String, url: String) {
        self.label = label
        self.url = url
    }
}

public struct SiteConfig: Equatable, Sendable, Codable {
    public var title: String
    public var author: String
    public var description: String
    public var url: String?
    public var theme: SiteTheme?
    /// Header navigation. When nil or empty, no nav is rendered at all.
    public var nav: [NavItem]?

    public init(
        title: String = "",
        author: String = "",
        description: String = "",
        url: String? = nil,
        theme: SiteTheme? = nil,
        nav: [NavItem]? = nil
    ) {
        self.title = title
        self.author = author
        self.description = description
        self.url = url
        self.theme = theme
        self.nav = nav
    }

    enum CodingKeys: String, CodingKey {
        case title, author, description, url, theme, nav
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url)
        theme = try? c.decodeIfPresent(SiteTheme.self, forKey: .theme)
        nav = try? c.decodeIfPresent([NavItem].self, forKey: .nav)
    }

    /// Loads and decodes `overprint.yml`. Throws a clear error if it is missing or malformed.
    public static func load(from url: URL) throws -> SiteConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw OverprintError.configNotFound(url)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw OverprintError.io("could not read \(url.lastPathComponent): \(error.localizedDescription)")
        }
        do {
            return try YAMLDecoder().decode(SiteConfig.self, from: data)
        } catch {
            throw OverprintError.invalidConfig(String(describing: error))
        }
    }

    /// Writes the config back to `overprint.yml` (used by "Create a new site" and the Build assistant).
    public func save(to url: URL) throws {
        do {
            let yaml = try YAMLEncoder().encode(self)
            try yaml.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw OverprintError.io("could not write \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}
