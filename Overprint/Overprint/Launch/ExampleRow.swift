import SwiftUI
import OverprintKit

/// An example site in the launch panel. It is a template, not a real site: clicking it copies the
/// example out and opens the copy, so the bundled original is never touched. Hovering reveals a
/// trash that removes the example from this onboarding list (it is bundled, so this only hides it).
struct ExampleRow: View {
    let example: ExampleLibrary.Example
    let action: () -> Void
    let onDismiss: () -> Void

    @State private var hovering = false

    var body: some View {
        // Not a Button, so the trash is its own hit target rather than a nested button.
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(OPColor.tileBg)
                    .frame(width: 38, height: 38)
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.black.opacity(0.07)))
                Image(systemName: example.icon)
                    .font(.system(size: 15))
                    .foregroundStyle(OPColor.textMuted)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(example.title)
                    .font(OPFont.ui(13.5, weight: .semibold))
                    .foregroundStyle(OPColor.ink)
                    .lineLimit(1)
                Text(example.summary)
                    .font(OPFont.ui(11.5))
                    .foregroundStyle(OPColor.textFaint)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            if hovering {
                Button(action: onDismiss) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(OPColor.textMuted)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.06)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHand()
                .help("Remove this example from the list")
            } else {
                Text("EXAMPLE")
                    .font(OPFont.mono(9, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(OPColor.textFainter)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.black.opacity(0.12)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 9).fill(hovering ? Color.black.opacity(0.055) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { hovering = $0 }
    }
}
