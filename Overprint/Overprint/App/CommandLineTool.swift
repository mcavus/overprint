import Foundation

/// Installs the `overprint` CLI that ships inside the app bundle onto the user's PATH, the way
/// VS Code installs `code`. The binary itself lives in `Contents/MacOS/` so it is covered by the
/// app's code signature; this only manages a symlink pointing at it.
enum CommandLineTool {
    enum InstallResult: Equatable {
        /// Linked, and the directory is already on PATH.
        case installed(path: String)
        /// Linked, but the user needs to add the directory to PATH themselves.
        case installedNeedsPath(path: String, directory: String)
        case failed(String)
    }

    /// The CLI inside this app bundle, or nil in a build where it was not embedded (Debug).
    ///
    /// It is named `overprint-cli` rather than `overprint` on purpose: macOS filesystems are
    /// case-insensitive, so `Contents/MacOS/overprint` is the same path as the app's own
    /// executable `Overprint`. The symlink this installs is still called `overprint`.
    static var bundledURL: URL? {
        guard let executables = Bundle.main.executableURL?.deletingLastPathComponent() else { return nil }
        let candidate = executables.appendingPathComponent("overprint-cli")
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }

    /// Preferred first, then a fallback that never needs an admin prompt.
    private static var candidateDirectories: [String] {
        ["/usr/local/bin", "\(NSHomeDirectory())/.local/bin"]
    }

    /// Where the symlink currently points, if it is ours.
    static var installedPath: String? {
        let fm = FileManager.default
        for dir in candidateDirectories {
            let link = "\(dir)/overprint"
            guard let target = try? fm.destinationOfSymbolicLink(atPath: link) else { continue }
            if target.contains("Overprint.app") { return link }
        }
        return nil
    }

    static func install() -> InstallResult {
        guard let source = bundledURL else {
            return .failed("This build does not include the command line tool.")
        }
        let fm = FileManager.default

        for dir in candidateDirectories {
            // Only create ~/.local/bin ourselves. Creating /usr/local/bin needs admin rights, and
            // silently failing there is better than prompting for a password unprompted.
            if !fm.fileExists(atPath: dir) {
                guard dir.hasPrefix(NSHomeDirectory()) else { continue }
                guard (try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)) != nil else { continue }
            }
            guard fm.isWritableFile(atPath: dir) else { continue }

            let link = "\(dir)/overprint"
            try? fm.removeItem(atPath: link) // replace a stale link from an older install
            do {
                try fm.createSymbolicLink(atPath: link, withDestinationPath: source.path)
            } catch {
                continue
            }
            return isOnPath(dir) ? .installed(path: link) : .installedNeedsPath(path: link, directory: dir)
        }

        return .failed("Could not write to /usr/local/bin or ~/.local/bin. You can link it yourself: ln -s \"\(source.path)\" /usr/local/bin/overprint")
    }

    static func uninstall() {
        let fm = FileManager.default
        for dir in candidateDirectories {
            let link = "\(dir)/overprint"
            guard let target = try? fm.destinationOfSymbolicLink(atPath: link), target.contains("Overprint.app") else { continue }
            try? fm.removeItem(atPath: link)
        }
    }

    /// A GUI app launched from Finder has a bare PATH, so consult the login shell instead of
    /// this process's environment, which would give a misleading answer.
    private static func isOnPath(_ directory: String) -> Bool {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", "echo $PATH"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let path = String(data: data, encoding: .utf8) ?? ""
        return path.split(separator: ":").contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == directory }
    }
}
