import Foundation

/// The example sites that ship inside the app, and the ability to copy one out.
///
/// They are copied rather than opened in place: anything inside the app bundle is read only and is
/// replaced on update, so an example you could not edit or delete would be a dead end. Once copied,
/// an example is an ordinary site folder you own.
public struct ExampleLibrary {
    public init() {}

    public struct Example: Identifiable, Sendable, Equatable {
        public var id: String { folder }
        /// Directory name inside the bundle.
        public let folder: String
        /// Title from the example's own overprint.yml.
        public let title: String
        public let summary: String
        /// SF Symbol name that suits the kind of site.
        public let icon: String

        public init(folder: String, title: String, summary: String, icon: String) {
            self.folder = folder
            self.title = title
            self.summary = summary
            self.icon = icon
        }
    }

    /// Ordered so the gentlest example comes first.
    private static let order = ["starter", "changelog", "journal"]

    private static let summaries = [
        "starter": "A personal writing blog. Start here: posts, frontmatter, and drafts.",
        "changelog": "A developer changelog, dark and monospaced. Tags and the command line.",
        "journal": "A studio journal on cream paper. Theming, pages, and navigation.",
    ]

    private static let icons = [
        "starter": "square.and.pencil",
        "changelog": "terminal",
        "journal": "paintbrush.pointed",
    ]

    private static var examplesRoot: URL? {
        Bundle.module.resourceURL?.appendingPathComponent("Examples")
    }

    /// Every example bundled with this build, in reading order.
    public func available() -> [Example] {
        guard let root = Self.examplesRoot else { return [] }
        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []

        return folders
            .filter { fm.fileExists(atPath: root.appendingPathComponent($0).appendingPathComponent("overprint.yml").path) }
            .sorted { (Self.order.firstIndex(of: $0) ?? .max) < (Self.order.firstIndex(of: $1) ?? .max) }
            .map { folder in
                let config = try? SiteConfig.load(from: root.appendingPathComponent(folder).appendingPathComponent("overprint.yml"))
                return Example(
                    folder: folder,
                    title: config?.title.isEmpty == false ? config!.title : folder,
                    summary: Self.summaries[folder] ?? config?.description ?? "",
                    icon: Self.icons[folder] ?? "doc.text"
                )
            }
    }

    /// Where copied examples live: `~/Documents/Overprint/<name>`. Somewhere the user can find,
    /// edit, and throw away, without being asked to choose a location for something they are
    /// only trying out.
    public func defaultDestination(for example: Example) -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        let base = documents.appendingPathComponent("Overprint")

        var candidate = base.appendingPathComponent(example.folder)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = base.appendingPathComponent("\(example.folder)-\(suffix)")
            suffix += 1
        }
        return candidate
    }

    /// Copies `example` somewhere sensible and returns the new site folder. No prompting.
    @discardableResult
    public func copyToDefaultLocation(_ example: Example) throws -> URL {
        let destination = defaultDestination(for: example)
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw OverprintError.io("could not create \(destination.deletingLastPathComponent().path): \(error.localizedDescription)")
        }
        return try copy(example, to: destination)
    }

    /// Copies `example` to `destination`, which must not already exist. Returns the new site folder.
    @discardableResult
    public func copy(_ example: Example, to destination: URL) throws -> URL {
        guard let root = Self.examplesRoot else {
            throw OverprintError.io("this build does not include the example sites")
        }
        let source = root.appendingPathComponent(example.folder)
        let fm = FileManager.default

        guard fm.fileExists(atPath: source.path) else {
            throw OverprintError.io("example \"\(example.folder)\" is missing from the app")
        }
        guard !fm.fileExists(atPath: destination.path) else {
            throw OverprintError.io("\(destination.lastPathComponent) already exists")
        }

        do {
            try fm.copyItem(at: source, to: destination)
        } catch {
            throw OverprintError.io("could not copy the example: \(error.localizedDescription)")
        }

        // Examples are copied verbatim from the bundle, which has no AGENTS.md, so add the same
        // contract document a scaffolded site gets. Otherwise the one path we steer new users to
        // produces the only kind of site without it.
        let agentsURL = destination.appendingPathComponent("AGENTS.md")
        if !fm.fileExists(atPath: agentsURL.path), let template = SiteScaffolder.agentsTemplate() {
            try? template.write(to: agentsURL, atomically: true, encoding: .utf8)
        }

        // Bundle resources are read only. Make the copy writable so it behaves like any other site.
        // Directories need the execute bit to stay traversable, so they are set separately.
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        if let items = fm.enumerator(at: destination, includingPropertiesForKeys: [.isDirectoryKey]) {
            for case let url as URL in items {
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                try? fm.setAttributes([.posixPermissions: isDirectory ? 0o755 : 0o644], ofItemAtPath: url.path)
            }
        }
        return destination
    }
}
