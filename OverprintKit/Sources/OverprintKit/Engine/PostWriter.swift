import Foundation

/// Creates new post files that follow the frozen frontmatter contract. Used by the app's
/// new-post button and the CLI `new` command.
public struct PostWriter {
    public init() {}

    /// Renders a string as a YAML double-quoted scalar, escapes included.
    ///
    /// The backslash must be escaped FIRST, or escaping the quote introduces backslashes that then
    /// get double-escaped. A title like `the \ key` or one carrying a newline would otherwise write
    /// frontmatter that no longer parses, and the post would fail its own validation.
    static func yamlQuoted(_ value: String) -> String {
        var out = ""
        out.reserveCapacity(value.count + 2)
        for character in value {
            switch character {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.append(character)
            }
        }
        return "\"\(out)\""
    }

    /// Writes `content/posts/YYYY-MM-DD-slug.md` with a starter frontmatter block, choosing a
    /// Renames a post file to match its own frontmatter, returning the new URL when it moved.
    ///
    /// A post created before its title exists is named `<date>-untitled.md`, and nothing renamed it
    /// when the title was filled in, so the filename, the slug and the date could all disagree.
    ///
    /// Only a name that already carries a date prefix is settled. A post at `hello.md` is following
    /// a looser convention that builds correctly, and `filenameDateIssue` deliberately does not even
    /// warn about it, so renaming it would be a change nobody asked for. A destination that already
    /// exists is left alone: two posts claiming one slug is a duplicate that `validate()` reports,
    /// and moving one on top of the other would destroy writing.
    @discardableResult
    public func renameToMatchFrontmatter(_ fileURL: URL) throws -> URL? {
        let filename = fileURL.lastPathComponent
        guard Self.hasDatePrefix(filename) else { return nil }
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8),
              let parsed = try? FrontmatterParser().parse(raw, filename: filename)
        else { return nil }

        // `parse` rejects an unsafe slug already. Checked again because this is the second place a
        // slug becomes a path on disk.
        guard FrontmatterParser.slugIssue(parsed.0.slug) == nil else { return nil }

        let wanted = "\(DateFormat.isoString(parsed.0.date))-\(parsed.0.slug).md"
        guard wanted != filename else { return nil }
        let destination = fileURL.deletingLastPathComponent().appendingPathComponent(wanted)
        guard !FileManager.default.fileExists(atPath: destination.path) else { return nil }

        do {
            try FileManager.default.moveItem(at: fileURL, to: destination)
        } catch {
            throw OverprintError.io("could not rename \(filename): \(error.localizedDescription)")
        }
        return destination
    }

    /// Whether a filename opens with `YYYY-MM-DD-`.
    static func hasDatePrefix(_ filename: String) -> Bool {
        let parts = filename.split(separator: "-", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2 else {
            return false
        }
        return parts[0].allSatisfy(\.isNumber) && parts[1].allSatisfy(\.isNumber)
            && parts[2].allSatisfy(\.isNumber) && !parts[3].isEmpty
    }

    /// unique filename. Returns the created file's URL.
    @discardableResult
    public func createPost(
        in siteURL: URL,
        title: String,
        date: Date = Date(),
        body: String = "Start writing…",
        tags: [String] = [],
        draft: Bool = true
    ) throws -> URL {
        let postsDir = siteURL.appendingPathComponent("content/posts")
        do {
            try FileManager.default.createDirectory(at: postsDir, withIntermediateDirectories: true)
        } catch {
            throw OverprintError.io("could not create content/posts: \(error.localizedDescription)")
        }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = trimmed.isEmpty ? "Untitled" : trimmed
        let baseSlug = Self.slugify(displayTitle)
        let dateString = DateFormat.isoString(date)

        var slug = baseSlug
        var counter = 2
        while FileManager.default.fileExists(atPath: postsDir.appendingPathComponent("\(dateString)-\(slug).md").path) {
            slug = "\(baseSlug)-\(counter)"
            counter += 1
        }

        let fileURL = postsDir.appendingPathComponent("\(dateString)-\(slug).md")
        let escapedTitle = Self.yamlQuoted(displayTitle)
        let tagsList = tags.isEmpty
            ? "[]"
            : "[" + tags.map(Self.yamlQuoted).joined(separator: ", ") + "]"
        let content = """
        ---
        title: \(escapedTitle)
        date: \(dateString)
        tags: \(tagsList)
        slug: \(slug)
        draft: \(draft)
        ---

        \(body)
        """
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw OverprintError.io("could not write \(fileURL.lastPathComponent): \(error.localizedDescription)")
        }
        return fileURL
    }

    /// Lowercases and reduces a title to an ASCII `a-z0-9-` slug.
    static func slugify(_ string: String) -> String {
        var out = ""
        for scalar in string.lowercased().unicodeScalars {
            if (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9") {
                out.unicodeScalars.append(scalar)
            } else {
                out.append("-")
            }
        }
        while out.contains("--") {
            out = out.replacingOccurrences(of: "--", with: "-")
        }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return out.isEmpty ? "untitled" : out
    }
}
