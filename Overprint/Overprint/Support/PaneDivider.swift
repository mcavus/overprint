import SwiftUI

/// A draggable vertical divider that moves a stored width directly.
///
/// The width is never measured back out of the laid-out view. Feeding a measured width into the
/// same stored value that drives the frame makes each layout pass trigger another write, and
/// another pass. The drag is the only thing here that changes the width.
struct PaneDivider: View {
    @Binding var width: Double
    let range: ClosedRange<Double>

    @State private var dragStart: Double?
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(OPColor.hairline)
            .frame(width: 1)
            .overlay {
                // A hairline is too thin to grab, so widen only the hit area.
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 9)
                    .contentShape(Rectangle())
            }
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStart ?? PaneWidth.clamp(width, to: range)
                        if dragStart == nil { dragStart = start }
                        width = min(max(start + value.translation.width, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in dragStart = nil }
            )
    }
}
