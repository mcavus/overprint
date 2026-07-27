import SwiftUI

/// The top bar: blog name / current mode.
struct BreadcrumbBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 9) {
            Text(model.currentSite?.displayName ?? "Overprint")
                .font(OPFont.ui(13.5, weight: .semibold))
                .foregroundStyle(OPColor.ink)
            Text("/")
                .foregroundStyle(OPColor.borderStrong)
            Text(model.mode.rawValue)
                .font(OPFont.ui(13))
                .foregroundStyle(Color(hex: 0x7A7A80))
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(OPColor.surface4)
        .overlay(alignment: .bottom) {
            Rectangle().fill(OPColor.hairline).frame(height: 1)
        }
    }
}
