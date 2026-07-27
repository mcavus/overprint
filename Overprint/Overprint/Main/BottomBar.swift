import SwiftUI
import AppKit

/// The bottom bar: live serving status on the left, mode-specific actions on the right.
/// Serve and Open control the local server; Commit and Deploy drive the git layer.
struct BottomBar: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var server: ServerManager

    @State private var showCommit = false
    @State private var showDeploy = false

    var body: some View {
        HStack(spacing: 10) {
            servingIndicator

            Spacer()

            if model.mode == .build {
                openButton
                deployButton
            } else {
                serveButton
                commitButton
                deployButton
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(OPColor.surface4)
        .overlay(alignment: .top) {
            Rectangle().fill(OPColor.hairline).frame(height: 1)
        }
        .sheet(isPresented: $showCommit) {
            if let site = model.currentSite?.url {
                CommitSheet(
                    git: model.gitManager,
                    site: site,
                    isPresented: $showCommit,
                    onSetUpPublishing: {
                        showCommit = false
                        // Let the commit sheet dismiss before presenting the deploy sheet.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showDeploy = true }
                    }
                )
            }
        }
        .sheet(isPresented: $showDeploy) {
            if let site = model.currentSite?.url {
                DeployDialog(git: model.gitManager, site: site, isPresented: $showDeploy)
            }
        }
    }

    private var servingIndicator: some View {
        HStack(spacing: 9) {
            if server.isServing {
                Circle().fill(OPColor.serving).frame(width: 8, height: 8)
                Text(verbatim: "Serving · localhost:\(server.port)")
                    .font(OPFont.mono(12))
                    .foregroundStyle(OPColor.textSecondary)
            } else {
                Circle().strokeBorder(Color(hex: 0xB0B0B6), lineWidth: 1.5).frame(width: 8, height: 8)
                Text("Server stopped")
                    .font(OPFont.mono(12))
                    .foregroundStyle(OPColor.textSecondary)
            }
        }
    }

    private var openButton: some View {
        Button {
            if let url = server.url { NSWorkspace.shared.open(url) }
        } label: {
            barLabel {
                Text("Open").font(OPFont.ui(13, weight: .medium))
                Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(OPColor.textFaint)
            }
        }
        .buttonStyle(.plain)
        .disabled(!server.isServing)
        .opacity(server.isServing ? 1 : 0.5)
    }

    private var serveButton: some View {
        Button { model.writeModel?.toggleServing() } label: {
            barLabel {
                if server.isServing {
                    RoundedRectangle(cornerRadius: 1.5).fill(OPColor.ink).frame(width: 8, height: 8)
                } else {
                    Image(systemName: "play.fill").font(.system(size: 9))
                }
                Text(server.isServing ? "Stop server" : "Start server").font(OPFont.ui(13, weight: .medium))
            }
        }
        .buttonStyle(.plain)
    }

    private var commitButton: some View {
        Button { showCommit = true } label: {
            barLabel {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 11))
                Text("Commit").font(OPFont.ui(13, weight: .medium))
            }
        }
        .buttonStyle(.plain)
    }

    private var deployButton: some View {
        Button { showDeploy = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up").font(.system(size: 11))
                Text("Deploy").font(OPFont.ui(13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(OPColor.accent))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A bordered, white bar button label (Open / Serve / Commit share this look).
    private func barLabel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 7) { content() }
            .foregroundStyle(OPColor.ink)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(OPColor.surface))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.black.opacity(0.14)))
            .contentShape(Rectangle())
    }
}
