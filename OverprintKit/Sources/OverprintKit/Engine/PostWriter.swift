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
