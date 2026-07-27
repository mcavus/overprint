import SwiftUI
import AppKit
import OverprintKit

/// The Xcode-style launch window: Create / Open on the left, Recents on the right.
struct LaunchView: View {
    @EnvironmentObject var model: AppModel

    private let examples = ExampleLibrary().available()

    /// The examples the user has not dismissed.
    private var visibleExamples: [ExampleLibrary.Example] {
        examples.filter { !model.hiddenExamples.contains($0.folder) }
    }

    /// Read from the bundle so the launch window can never drift from what actually shipped.
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        // Releases build with CFBundleVersion == CFBundleShortVersionString (see Scripts/release.sh,
        // where Sparkle's version comparison depends on it), so showing both reads as "0.1.0 (0.1.0)".
        // Only show the build number when it actually says something the version does not.
        guard build != short else { return "Version \(short)" }
        return "Version \(short) (\(build))"
    }

    var body: some View {
        HStack(spacing: 0) {
            leftPanel
            rightPanel
        }
        .frame(width: 760, height: 474)
        .background(OPColor.surface)
    }


    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image("overprint-lockup")
                .resizable()
                .scaledToFit()
                .frame(width: 194)
                .padding(.bottom, 15)

            Text("Write, build, and publish a blog.")
                .font(OPFont.ui(13))
                .foregroundStyle(OPColor.textSecondary)
                .padding(.bottom, 4)

            Text(Self.versionString)
                .font(OPFont.mono(11))
                .foregroundStyle(OPColor.textFainter)
                .padding(.bottom, 32)

            LaunchActionButton(
                icon: "plus",
                title: "Create a new site…",
                subtitle: "Scaffold a fresh blog with Claude",
                action: createNew
            )
            LaunchActionButton(
                icon: "folder",
                title: "Open a site…",
                subtitle: "Open an existing folder",
                action: chooseAndOpen
            )

            Spacer()

            Toggle(isOn: Binding(
                get: { model.showLaunchAtStart },
                set: { model.setShowLaunchAtStart($0) }
            )) {
                Text("Show this window when Overprint opens")
                    .font(OPFont.ui(12))
                    .foregroundStyle(OPColor.textMuted)
            }
            .toggleStyle(.checkbox)
        }
        .padding(EdgeInsets(top: 64, leading: 34, bottom: 24, trailing: 34))
        .frame(width: 322)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.black.opacity(0.07)).frame(width: 1)
        }
    }

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recents")
                    .font(OPFont.mono(11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(OPColor.textFaint)
                Spacer()
                Button("Clear") { model.clearRecents() }
                    .buttonStyle(.plain)
                    .font(OPFont.ui(12))
                    .foregroundStyle(OPColor.textFainter)
            }
            .padding(EdgeInsets(top: 20, leading: 22, bottom: 10, trailing: 22))

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(model.recents) { recent in
                        RecentRow(recent: recent, action: { open(recent.url) }, onTrash: { trash(recent) })
                            .contextMenu {
                                Button("Remove from Recents") { model.removeRecent(recent) }
                                Button("Move to Trash…") { trash(recent) }
                            }
                    }

                    if !visibleExamples.isEmpty {
                        HStack {
                            Text("Examples")
                                .font(OPFont.mono(11, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(OPColor.textFaint)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, model.recents.isEmpty ? 0 : 16)
                        .padding(.bottom, 6)

                        ForEach(visibleExamples) { example in
                            ExampleRow(
                                example: example,
                                action: { openExample(example) },
                                onDismiss: { model.hideExample(example.folder) }
                            )
                        }

                        Text("Opening one makes an editable copy. The trash icon removes it from this list.")
                            .font(OPFont.ui(11))
                            .foregroundStyle(OPColor.textFainter)
                            .fixedSize(horizontal: false, vertical: true)
                            // The enclosing VStack centers by default. The rows fill the width so it
                            // never shows on them, but this caption sizes to its own text and would
                            // sit indented from the Recents and Examples headers above it.
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(OPColor.surface3)
    }

    // MARK: Actions

    private func chooseAndOpen() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose an Overprint site folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    private func open(_ url: URL) {
        do {
            try model.openSite(at: url)
        } catch {
            presentAlert(title: "Couldn't open site", error: error)
        }
    }

    private func createNew() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.prompt = "Create"
        panel.message = "Choose where to create your new site"
        panel.nameFieldLabel = "Site folder:"
        panel.nameFieldStringValue = "my-site"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.createSite(at: url)
        } catch {
            presentAlert(title: "Couldn't create site", error: error)
        }
    }

    /// Copies the example to Documents and opens it. No prompting: it is a thing you try, not a
    /// project you are committing to, and the copy is deletable like any other site.
    private func openExample(_ example: ExampleLibrary.Example) {
        do {
            let url = try ExampleLibrary().copyToDefaultLocation(example)
            try model.openSite(at: url)
        } catch {
            presentAlert(title: "Couldn't open the example", error: error)
        }
    }

    /// Moves a site to the Trash after confirming. Recoverable, unlike deleting outright.
    private func trash(_ recent: RecentSite) {
        let alert = NSAlert()
        alert.messageText = "Move \"\(recent.name)\" to the Trash?"
        alert.informativeText = "The folder \(recent.path) will be moved to the Trash. You can put it back from there."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        NSWorkspace.shared.recycle([recent.url]) { _, error in
            DispatchQueue.main.async {
                if let error {
                    presentAlert(title: "Couldn't move to the Trash", error: error)
                } else {
                    model.removeRecent(recent)
                }
            }
        }
    }

    private func presentAlert(title: String, error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = (error as? OverprintError)?.description ?? error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

/// A Create / Open row: 42px symbol tile, title, and subtitle.
private struct LaunchActionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(OPColor.tileBg)
                        .frame(width: 42, height: 42)
                        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.black.opacity(0.07)))
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(hex: 0x3A3A3E))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(OPFont.ui(14, weight: .semibold))
                        .foregroundStyle(OPColor.ink)
                    Text(subtitle)
                        .font(OPFont.ui(12))
                        .foregroundStyle(OPColor.textMuted)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 10).fill(hovering ? Color.black.opacity(0.05) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A Recents row: letter-tile favicon, name, abbreviated path, relative time. On hover the time
/// is replaced by a trash button, so a site (including an opened example) can be deleted here
/// without going to Finder.
private struct RecentRow: View {
    let recent: RecentSite
    let action: () -> Void
    var onTrash: (() -> Void)? = nil

    @State private var hovering = false

    var body: some View {
        // Not a Button, so the trash control below is its own hit target rather than a nested
        // button, which macOS handles unreliably.
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(OPColor.ink).frame(width: 38, height: 38)
                Text(letter)
                    .font(OPFont.ui(16, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(recent.name)
                    .font(OPFont.ui(13.5, weight: .semibold))
                    .foregroundStyle(OPColor.ink)
                    .lineLimit(1)
                Text(abbreviatedPath)
                    .font(OPFont.mono(11.5))
                    .foregroundStyle(OPColor.textFaint)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if hovering, let onTrash {
                Button(action: onTrash) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(OPColor.textMuted)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.06)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Move this site to the Trash")
            } else {
                Text(whenText)
                    .font(OPFont.ui(11.5))
                    .foregroundStyle(OPColor.textFainter)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 9).fill(hovering ? Color.black.opacity(0.055) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { hovering = $0 }
    }

    private var letter: String { String(recent.name.first ?? "?").uppercased() }
    private var abbreviatedPath: String { (recent.path as NSString).abbreviatingWithTildeInPath }
    private var whenText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: recent.lastOpened, relativeTo: Date())
    }
}
