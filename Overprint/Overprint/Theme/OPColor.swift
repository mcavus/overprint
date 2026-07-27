import SwiftUI

/// The Overprint palette, from CLAUDE.md. Monochrome chrome with a single blue accent.
enum OPColor {
    static let ink = Color(hex: 0x1D1D1F)
    static let textSecondary = Color(hex: 0x6B6B70)
    static let textMuted = Color(hex: 0x8A8A90)
    static let textFaint = Color(hex: 0x9A9AA0)
    static let textFainter = Color(hex: 0xA6A6AC)

    static let accent = Color(hex: 0x0A7AFF)
    static let accentPressed = Color(hex: 0x0062CC)

    static let surface = Color.white
    static let surface2 = Color(hex: 0xFBFBFC)
    static let surface3 = Color(hex: 0xFAFAFB)
    static let surface4 = Color(hex: 0xF6F6F7)
    static let surface5 = Color(hex: 0xF2F2F4)

    static let railBg = Color(hex: 0xEDEDF0)
    static let tileBg = Color(hex: 0xF1F1F4)

    static let border = Color(hex: 0xECECEF)
    static let border2 = Color(hex: 0xE6E6EA)
    static let borderStrong = Color(hex: 0xCDCED4)

    static let serving = Color(hex: 0x28C840)

    /// A hairline border like the prototype's rgba(0,0,0,0.08).
    static let hairline = Color.black.opacity(0.08)
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
