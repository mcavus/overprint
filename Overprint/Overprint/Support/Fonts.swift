import AppKit
import CoreText

/// Registers the bundled JetBrains Mono faces at launch so the editor and mono labels can
/// use them. If registration ever fails, `OPFont.mono` falls back to SF Mono.
enum Fonts {
    static let familyName = "JetBrains Mono"

    static func registerBundled() {
        var urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        if let inFolder = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") {
            urls += inFolder
        }
        for url in urls {
            var error: Unmanaged<CFError>?
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }

    /// Evaluated lazily on first use, which happens after `registerBundled()` runs at launch.
    static let isMonoAvailable: Bool = NSFont(name: familyName, size: 12) != nil
}
