import SwiftUI

/// Remembered widths for the resizable panes, and the limits they move between.
enum PaneWidth {
    /// The posts list is a table of contents, not a workspace: it should take as little as it can
    /// while staying readable, leaving the room to the editor and the preview.
    static let postsDefault: Double = 214
    static let postsRange: ClosedRange<Double> = 170...360

    static let assistantDefault: Double = 400
    static let assistantRange: ClosedRange<Double> = 320...640

    static let editorMin: Double = 300
    static let previewMin: Double = 260

    /// `@AppStorage` returns whatever is on disk without consulting the range, and the range can
    /// change between versions. Clamp on read rather than writing a correction back, so reading a
    /// width stays free of side effects.
    static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
