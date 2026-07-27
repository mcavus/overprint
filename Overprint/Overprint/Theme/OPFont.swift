import SwiftUI

/// App chrome uses the system font (SF Pro). The mono is JetBrains Mono (bundled), with
/// SF Mono as the fallback if the bundled font is unavailable.
enum OPFont {
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if Fonts.isMonoAvailable {
            return .custom(Fonts.familyName, fixedSize: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }
}
