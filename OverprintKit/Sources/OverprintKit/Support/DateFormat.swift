import Foundation

/// Date helpers pinned to the frozen `YYYY-MM-DD` on-disk format. Formatters are built
/// per call (cheap at our scale) so there is no shared mutable state under Swift 6.
enum DateFormat {
    private static func formatter(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = pattern
        return f
    }

    /// Parses a `yyyy-MM-dd` string, or nil if it does not match.
    static func parse(_ string: String) -> Date? {
        formatter("yyyy-MM-dd").date(from: string)
    }

    /// The on-disk ISO date, e.g. `2026-07-16`.
    static func isoString(_ date: Date) -> String {
        formatter("yyyy-MM-dd").string(from: date)
    }

    /// The display date used in post meta, e.g. `JUL 16, 2026`.
    static func displayString(_ date: Date) -> String {
        formatter("MMM d, yyyy").string(from: date).uppercased()
    }

    /// RFC-822 date for RSS `pubDate`, e.g. `Thu, 16 Jul 2026 00:00:00 +0000`.
    static func rfc822String(_ date: Date) -> String {
        formatter("EEE, dd MMM yyyy HH:mm:ss Z").string(from: date)
    }
}
