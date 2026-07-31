import SwiftUI

/// Remembered widths for the resizable panes.
///
/// `HSplitView` does not persist its divider positions, so without this every launch resets the
/// layout to the defaults and any adjustment has to be made again.
enum PaneWidth {
    static let postsDefault: Double = 248
    static let postsMin: Double = 180
    static let postsMax: Double = 420

    static let assistantDefault: Double = 432
    static let assistantMin: Double = 320
    static let assistantMax: Double = 720

    static let editorMin: Double = 320
    static let previewMin: Double = 280
}
