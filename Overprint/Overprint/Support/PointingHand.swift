import SwiftUI
import AppKit

/// The pointing-hand cursor over the app's custom controls.
///
/// AppKit leaves the arrow in place over a button, because on macOS the pointing hand belongs to
/// links. That reads correctly for a bordered button, which announces itself by its chrome, but
/// most of Overprint's controls are bare rows and tiles, and under the cursor they are
/// indistinguishable from the surface behind them.
private struct PointingHand: ViewModifier {
    /// A `.disabled()` applied further out reaches here through the environment, so a control that
    /// cannot be clicked keeps the arrow.
    @Environment(\.isEnabled) private var isEnabled
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                setPushed(inside && isEnabled)
            }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled { setPushed(false) }
            }
            // A row can be removed from the list while the cursor is still inside it, and the
            // matching exit never arrives. The push would then outlive the view it belonged to and
            // leave the whole app showing a hand.
            .onDisappear {
                setPushed(false)
            }
    }

    /// Every push has to be matched by exactly one pop, so the pushed state is tracked rather than
    /// inferred from the hover callbacks, which do not always arrive in pairs.
    private func setPushed(_ want: Bool) {
        guard want != pushed else { return }
        pushed = want
        if want { NSCursor.pointingHand.push() } else { NSCursor.pop() }
    }
}

extension View {
    /// Marks a custom control as clickable. Use it on anything that acts like a button but does
    /// not draw button chrome; the system controls already handle their own cursor.
    func pointingHand() -> some View { modifier(PointingHand()) }
}
