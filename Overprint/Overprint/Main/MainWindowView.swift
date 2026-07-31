import SwiftUI

/// The main site window shell: mode rail on the left; breadcrumb, mode content, and the
/// bottom bar stacked on the right.
struct MainWindowView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            ModeRail()
            VStack(spacing: 0) {
                BreadcrumbBar()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                BottomBar(server: model.serverManager)
            }
        }
        .frame(minWidth: 900, idealWidth: 1160, maxWidth: .infinity,
               minHeight: 560, idealHeight: 724, maxHeight: .infinity)
        .background(OPColor.surface)
    }

    @ViewBuilder private var content: some View {
        switch model.mode {
        case .build:
            if let buildModel = model.buildModel {
                BuildView(model: buildModel, server: model.serverManager, ai: model.aiManager)
            } else {
                NoSiteView()
            }
        case .write:
            if let writeModel = model.writeModel {
                WriteView(model: writeModel, server: model.serverManager, ai: model.aiManager)
            } else {
                NoSiteView()
            }
        }
    }
}

/// Shown when the window has no open site, which should not normally happen: opening a site
/// creates both models. It exists so a failed open shows something rather than an empty pane.
private struct NoSiteView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 34))
                .foregroundStyle(OPColor.borderStrong)
            Text("No site open")
                .font(OPFont.ui(17, weight: .semibold))
                .foregroundStyle(OPColor.ink)
            Text("Open a site from the launch window to start writing.")
                .font(OPFont.ui(13))
                .foregroundStyle(OPColor.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OPColor.surface)
    }
}
