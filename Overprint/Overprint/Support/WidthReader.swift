import SwiftUI

/// Reports its own width whenever it changes.
///
/// `HSplitView` moves a pane by changing its layout, and offers no binding to observe. Placing
/// this in the pane's background is how a dragged width becomes something we can persist.
struct WidthReader: View {
    let onChange: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onChange(of: proxy.size.width) { _, width in
                    guard width > 1 else { return }
                    onChange(width)
                }
        }
    }
}
