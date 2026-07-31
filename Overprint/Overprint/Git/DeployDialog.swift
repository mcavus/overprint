import SwiftUI

/// Publishes the site to GitHub Pages. The first time, it asks for the repository and URL once and
/// remembers them; after that it is a single button.
struct DeployDialog: View {
    @ObservedObject var git: GitManager
    let site: URL
    @Binding var isPresented: Bool

    @State private var editing = false
    @State private var repository = ""
    @State private var url = ""
    @State private var connectError: String?
    @State private var busyConnecting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up").font(.system(size: 13, weight: .semibold)).foregroundStyle(OPColor.textSecondary)
                Text("Deploy").font(OPFont.ui(14, weight: .semibold)).foregroundStyle(OPColor.ink)
                Spacer()
            }

            if git.connection.isConnected && !editing {
                connectedView
            } else {
                connectForm
            }
        }
        .padding(18)
        .frame(width: 420)
        .task {
            await git.refresh(site: site)
            if repository.isEmpty { repository = git.connection.repository ?? "" }
            if url.isEmpty { url = git.connection.url ?? "" }
        }
        .onDisappear { git.resetDeploy() }
    }

    // MARK: Connected: one-click deploy

    private var connectedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                infoRow("Repository", git.connection.repository ?? "")
                if let site = git.connection.url, !site.isEmpty {
                    infoRow("Published at", site)
                }
                infoRow("Branch", GitManager.publishBranch)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OPColor.surface5, in: RoundedRectangle(cornerRadius: 10))

            Text("Builds the site (drafts excluded) and force-pushes it to \(GitManager.publishBranch).")
                .font(OPFont.ui(11.5))
                .foregroundStyle(OPColor.textFaint)

            if !git.deploySteps.isEmpty { stepsView }

            if case .error(let message) = git.deployPhase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(OPFont.ui(12.5)).foregroundStyle(Color(hex: 0xC0392B))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if git.deployPhase == .done {
                Text("Published. GitHub Pages can take a minute to go live.")
                    .font(OPFont.ui(12)).foregroundStyle(OPColor.serving)
            }

            HStack {
                if git.deployPhase == .done {
                    // Nothing more to do after a successful deploy: one button that closes.
                    Spacer()
                    primaryButton("Done", enabled: true) { isPresented = false }
                } else {
                    Button("Change…") { editing = true }
                        .buttonStyle(.plain)
                        .pointingHand()
                        .font(OPFont.ui(12))
                        .foregroundStyle(OPColor.textSecondary)
                    Spacer()
                    Button("Cancel") { isPresented = false }
                        .buttonStyle(.plain)
                        .pointingHand()
                        .font(OPFont.ui(13))
                        .foregroundStyle(OPColor.textSecondary)
                    primaryButton(git.deployPhase == .working ? "Deploying…" : "Deploy", enabled: git.deployPhase != .working) {
                        Task { await git.deploy(site: site) }
                    }
                }
            }
        }
    }

    // MARK: Not connected (or editing): one-time setup

    private var connectForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(git.connection.isConnected ? "Update where this site publishes." : "Connect this site to a GitHub repository. You only do this once.")
                .font(OPFont.ui(12))
                .foregroundStyle(OPColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            field("GitHub repository", "https://github.com/user/repo.git", $repository)
            field("Published URL", "https://blog.example.com", $url)

            if let connectError {
                Label(connectError, systemImage: "exclamationmark.triangle.fill")
                    .font(OPFont.ui(12.5)).foregroundStyle(Color(hex: 0xC0392B))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if editing {
                    Button("Back") { editing = false; connectError = nil }
                        .buttonStyle(.plain).font(OPFont.ui(13)).foregroundStyle(OPColor.textSecondary)
                }
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.plain).font(OPFont.ui(13)).foregroundStyle(OPColor.textSecondary)
                primaryButton(
                    busyConnecting ? "Connecting…" : (editing ? "Save" : "Connect"),
                    enabled: !busyConnecting && !repository.trimmingCharacters(in: .whitespaces).isEmpty
                ) {
                    Task { await connect() }
                }
            }
        }
    }

    private func connect() async {
        busyConnecting = true
        connectError = await git.connect(site: site, repository: repository, url: url)
        busyConnecting = false
        if connectError == nil { editing = false }
    }

    // MARK: Pieces

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(OPFont.mono(10.5, weight: .semibold))
                .foregroundStyle(OPColor.textFaint)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(OPFont.mono(12))
                .foregroundStyle(OPColor.ink)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func field(_ label: String, _ placeholder: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(OPFont.mono(10.5, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(OPColor.textFaint)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(OPFont.mono(12.5))
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.black.opacity(0.14)))
        }
    }

    private func primaryButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(OPFont.ui(13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(OPColor.accent))
                .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .pointingHand()
        .disabled(!enabled)
    }

    private var stepsView: some View {
        VStack(spacing: 0) {
            ForEach(Array(git.deploySteps.enumerated()), id: \.element.id) { index, step in
                HStack(spacing: 10) {
                    stepIcon(step.status)
                    Text(step.label).font(OPFont.ui(12.5)).foregroundStyle(OPColor.ink)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                if index < git.deploySteps.count - 1 {
                    Rectangle().fill(Color.black.opacity(0.05)).frame(height: 1)
                }
            }
        }
        .background(OPColor.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.black.opacity(0.09)))
    }

    @ViewBuilder private func stepIcon(_ status: GitManager.Step.Status) -> some View {
        switch status {
        case .done:
            ZStack {
                Circle().fill(OPColor.ink).frame(width: 15, height: 15)
                Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
            }
        case .active:
            ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 15, height: 15)
        case .pending:
            Circle().strokeBorder(Color.black.opacity(0.14), lineWidth: 1.6).frame(width: 14, height: 14)
        case .failed:
            ZStack {
                Circle().fill(Color(hex: 0xC0392B)).frame(width: 15, height: 15)
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
            }
        }
    }
}
