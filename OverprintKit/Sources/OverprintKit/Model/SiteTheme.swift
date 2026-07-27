import Foundation

/// Per-site theme tokens stored under `theme:` in `overprint.yml`. Kept deliberately small
/// so the Build assistant can set them from a structured spec (no bespoke CSS).
public struct SiteTheme: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable {
        case light
        case dark
    }

    public enum Font: String, Codable, Sendable {
        case serif
        case sans
        case mono
    }

    public var mode: Mode
    public var accent: String
    public var font: Font
    /// Optional page background (paper) color. When set, overrides the mode's default paper,
    /// so a site can be e.g. cream without switching to dark mode. Nil keeps the mode default.
    public var background: String?

    public init(mode: Mode = .light, accent: String = "#0A7AFF", font: Font = .serif, background: String? = nil) {
        self.mode = mode
        self.accent = accent
        self.font = font
        self.background = background
    }

    enum CodingKeys: String, CodingKey {
        case mode, accent, font, background
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? c.decode(Mode.self, forKey: .mode)) ?? .light
        accent = (try? c.decode(String.self, forKey: .accent)) ?? "#0A7AFF"
        font = (try? c.decode(Font.self, forKey: .font)) ?? .serif
        background = try? c.decodeIfPresent(String.self, forKey: .background)
    }
}
