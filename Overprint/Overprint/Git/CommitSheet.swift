import SwiftUI
import OverprintKit

/// Commit the site's source with a message. When the site is connected to GitHub, this also pushes.
/// There is no repository to enter: it uses the one the site remembers.
struct CommitSheet: View {
    @ObservedObject var git: GitManager
    let site: URL
    @Binding var isPresented: Bool
    /// Opens the Deploy sheet, which is also where a site gets connected to GitHub.
    let onSetUpPublishing: () -> Void

    @State private var message = ""

    private var hasWork: Bool {
        !git.connection.isRepository || (git.pending.map { !$0.isEmpty } ?? git.connection.hasChanges)
    }

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

            fileList

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
        .frame(width: 440)
        .task { await git.refresh(site: site) }
        .onDisappear { git.resetCommit() }
    }

    /// What the commit is about to send, with drafts flagged.
    ///
    /// A draft is left out of the built site, but its Markdown still goes into the repository, and
    /// on a public repo that text is readable.
    @ViewBuilder private var fileList: some View {
        if let pending = git.pending, !pending.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("\(pending.files.count) file\(pending.files.count == 1 ? "" : "s")")
                        .foregroundStyle(OPColor.textFaint)
                    if !pending.drafts.isEmpty {
                        Text("·").foregroundStyle(OPColor.textFainter)
                        Text("\(pending.drafts.count) draft\(pending.drafts.count == 1 ? "" : "s")")
                            .foregroundStyle(OPColor.ink)
                    }
                    Spacer()
                }
                .font(OPFont.mono(11))

                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(visibleFiles(pending)) { file in
                            fileRow(file)
                        }
                        if let hidden = hiddenCount(pending) {
                            Text("+ \(hidden) more file\(hidden == 1 ? "" : "s")")
                                .font(OPFont.mono(11))
                                .foregroundStyle(OPColor.textFainter)
                                .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .frame(maxHeight: 168)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.black.opacity(0.10)))

                if !pending.drafts.isEmpty {
                    Text("Drafts are committed as source. Deploy leaves them off the published site.")
                        .font(OPFont.ui(11))
                        .foregroundStyle(OPColor.textFainter)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func fileRow(_ file: CommitPreview.File) -> some View {
        HStack(spacing: 7) {
            Text(file.change.rawValue)
                .font(OPFont.mono(11))
                .foregroundStyle(OPColor.textFainter)
                .frame(width: 58, alignment: .leading)
            if file.isDraft {
                Text("DRAFT")
                    .font(OPFont.mono(9, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(OPColor.textSecondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.black.opacity(0.18)))
            }
            Text(file.title ?? file.path)
                .font(OPFont.mono(11.5))
                .foregroundStyle(file.isDraft ? OPColor.ink : OPColor.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .help(file.path)
    }

    /// Every draft, plus a bounded number of the rest. Drafts sort first in the preview, so the
    /// flagged rows are never the ones the cap drops.
    private func visibleFiles(_ pending: CommitPreview) -> [CommitPreview.File] {
        let limit = max(pending.drafts.count + 10, 12)
        return Array(pending.files.prefix(limit))
    }

    private func hiddenCount(_ pending: CommitPreview) -> Int? {
        let shown = visibleFiles(pending).count
        return pending.files.count > shown ? pending.files.count - shown : nil
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
