import SwiftUI

/// Commit the site's source with a message. When the site is connected to GitHub, this also pushes.
/// There is no repository to enter: it uses the one the site remembers.
struct CommitSheet: View {
    @ObservedObject var git: GitManager
    let site: URL
    @Binding var isPresented: Bool
    /// Opens the Deploy sheet, which is also where a site gets connected to GitHub.
    let onSetUpPublishing: () -> Void

    @State private var message = ""

    private var hasWork: Bool { !git.connection.isRepository || git.connection.hasChanges }

    private var canCommit: Bool {
        guard git.commitPhase != .working else { return false }
        if !hasWork { return false }
        return !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 13)).foregroundStyle(OPColor.textSecondary)
                Text("Commit changes").font(OPFont.ui(14, weight: .semibold)).foregroundStyle(OPColor.ink)
                Spacer()
            }

            Text(statusLine)
                .font(OPFont.mono(11.5))
                .foregroundStyle(OPColor.textFaint)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Message (e.g. Add a new post)", text: $message, axis: .vertical)
                .textFieldStyle(.plain)
                .font(OPFont.ui(13))
                .lineLimit(1...4)
                .padding(9)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.black.opacity(0.14)))
                .disabled(git.commitPhase == .working)

            if !git.connection.isConnected {
                Button(action: onSetUpPublishing) {
                    Text("Connect to GitHub to push and publish…")
                        .font(OPFont.ui(12))
                        .foregroundStyle(OPColor.accent)
                }
                .buttonStyle(.plain)
                .pointingHand()
            }

            phaseView

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .font(OPFont.ui(13))
                    .foregroundStyle(OPColor.textSecondary)
                Button {
                    Task { await runCommit() }
                } label: {
                    Text(actionTitle)
                        .font(OPFont.ui(13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 8).fill(OPColor.accent))
                        .opacity(canCommit ? 1 : 0.5)
                }
                .buttonStyle(.plain)
                .pointingHand()
                .disabled(!canCommit)
            }
        }
        .padding(18)
        .frame(width: 380)
        .task { await git.refresh(site: site) }
        .onDisappear { git.resetCommit() }
    }

    private var actionTitle: String {
        if git.commitPhase == .working { return "Working…" }
        return git.connection.isConnected ? "Commit and push" : "Commit"
    }

    private var statusLine: String {
        guard git.connection.isRepository else { return "Not a git repo yet. This creates one and commits." }
        let branch = git.connection.branch ?? "main"
        if let repo = git.connection.repository {
            return git.connection.hasChanges ? "Branch \(branch) · pushing to \(repo)" : "Branch \(branch) · nothing to commit"
        }
        return git.connection.hasChanges ? "Branch \(branch) · not connected to GitHub" : "Branch \(branch) · nothing to commit"
    }

    @ViewBuilder private var phaseView: some View {
        switch git.commitPhase {
        case .done:
            Label(git.connection.isConnected ? "Committed and pushed." : "Committed.", systemImage: "checkmark.circle.fill")
                .font(OPFont.ui(12.5)).foregroundStyle(OPColor.serving)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(OPFont.ui(12.5)).foregroundStyle(Color(hex: 0xC0392B))
                .fixedSize(horizontal: false, vertical: true)
        default:
            EmptyView()
        }
    }

    private func runCommit() async {
        await git.commit(site: site, message: message)
        if git.commitPhase == .done {
            try? await Task.sleep(nanoseconds: 900_000_000)
            isPresented = false
        }
    }
}
