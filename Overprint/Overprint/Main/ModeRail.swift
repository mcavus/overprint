import SwiftUI

/// The far-left rail: the mark, Build and Write tiles (active tile is the blue rounded
/// square), and a settings gear at the bottom.
struct ModeRail: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 4) {
            Button { model.closeSite() } label: {
                Image("overprint-mark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close this site and go back to the launch window")
            .padding(.top, 44)
            .padding(.bottom, 14)

            Rectangle()
                .fill(Color.black.opacity(0.1))
                .frame(width: 30, height: 1)
                .padding(.bottom, 14)

            RailTile(icon: "bubble.left.and.bubble.right", label: "Build", active: model.mode == .build) {
                model.mode = .build
            }
            // `square.and.pencil` draws its pencil above and right of the square, so the glyph's
            // ink sits low-left inside a bounding box SwiftUI centres. Nudge it back optically.
            RailTile(icon: "square.and.pencil", label: "Write", active: model.mode == .write,
                     iconOffset: CGSize(width: 1, height: 1)) {
                model.mode = .write
            }

            Spacer()

            Button { openSettings() } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .foregroundStyle(OPColor.textMuted)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)
        }
        .frame(width: 77)
        .frame(maxHeight: .infinity)
        .background(OPColor.railBg)
        .overlay(alignment: .trailing) {
            Rectangle().fill(OPColor.hairline).frame(width: 1)
        }
    }
}

private struct RailTile: View {
    let icon: String
    let label: String
    let active: Bool
    /// Optical correction for glyphs whose ink is not centred in their bounding box.
    var iconOffset: CGSize = .zero
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(active ? OPColor.accent : (hovering ? Color.black.opacity(0.05) : .clear))
                        .frame(width: 34, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(active ? Color.white : OPColor.textMuted)
                        .offset(x: iconOffset.width, y: iconOffset.height)
                }
                Text(label)
                    .font(OPFont.ui(10, weight: active ? .semibold : .medium))
                    .foregroundStyle(active ? OPColor.ink : OPColor.textFaint)
            }
            .frame(width: 52)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
