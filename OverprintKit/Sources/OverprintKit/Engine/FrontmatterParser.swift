import Foundation
import Yams

/// Splits a post file into its YAML frontmatter and Markdown body, then validates the
/// frontmatter against the frozen contract. Validation issues are collected per file so
/// both `build` and `validate` can report precise messages.
public struct FrontmatterParser {
    public init() {}

    /// Splits raw file content into the frontmatter YAML block and the Markdown body.
    /// Returns `nil` YAML if the file does not begin with a `---` fence.
    /// Reads just `draft` and `title`, without validating the rest of the contract.
    ///
    /// A post whose required fields are broken still has to report its draft flag: the commit
    /// preview exists to warn before the text is pushed, and a post that fails validation is
    /// exactly when that matters. Nothing read here ever becomes a filename, which is why it can
    /// skip `slugIssue`.
    static func draftAndTitle(inRaw raw: String) -> (isDraft: Bool, title: String?) {
        let (yaml, _) = FrontmatterParser().split(raw)
        guard let yaml, let dict = (try? Yams.load(yaml: yaml)) as? [String: Any] else { return (false, nil) }
        let title = (dict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ((dict["draft"] as? Bool) ?? false, (title?.isEmpty == false) ? title : nil)
    }

    public func split(_ raw: String) -> (yaml: String?, body: String) {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        guard lines.first == "---" else { return (nil, raw) }

        var closeIndex: Int?
        for i in 1..<lines.count where lines[i] == "---" {
            closeIndex = i
            break
        }
        guard let close = closeIndex else { return (nil, raw) }

        let yaml = lines[1..<close].joined(separator: "\n")
        var body = lines[(close + 1)...].joined(separator: "\n")
        while body.hasPrefix("\n") { body.removeFirst() }
        return (yaml, body)
    }

    /// Parses a post file's content and filename into a validated `Post` plus its body.
    public func parse(_ raw: String, filename: String) throws -> (post: Post, body: String) {
        let (yaml, body) = split(raw)
        guard let yaml else {
            throw OverprintError.postValidation(file: filename, issues: ["missing frontmatter block (file must start with ---)"])
        }

        let loaded: Any?
        do {
            loaded = try Yams.load(yaml: yaml)
        } catch {
            throw OverprintError.postValidation(file: filename, issues: ["invalid YAML frontmatter: \(error)"])
        }
        guard let dict = loaded as? [String: Any] else {
            throw OverprintError.postValidation(file: filename, issues: ["frontmatter is not a key/value mapping"])
        }

        var issues: [String] = []

        let title = (dict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if title == nil || title?.isEmpty == true {
            issues.append("missing required field: title")
        }

        var date: Date?
        if let d = dict["date"] as? Date {
            date = d
        } else if let s = dict["date"] as? String, let parsed = DateFormat.parse(s) {
            date = parsed
        } else if dict["date"] == nil {
            issues.append("missing required field: date")
        } else {
            issues.append("date must be in YYYY-MM-DD form")
        }

        let slugField = (dict["slug"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = (slugField?.isEmpty == false) ? slugField! : Self.slug(fromFilename: filename)
        if let issue = Self.slugIssue(slug) { issues.append(issue) }
        let tags = Self.stringArray(dict["tags"])
        let draft = (dict["draft"] as? Bool) ?? false

        if !issues.isEmpty {
            throw OverprintError.postValidation(file: filename, issues: issues)
        }

        let post = Post(title: title!, date: date!, tags: tags, slug: slug, draft: draft,
                        description: Self.optionalString(dict["description"]))
        return (post, body)
    }

    /// Parses a standalone page. Same contract as a post minus `date`, `tags`, and ordering:
    /// only `title` is required, with `slug` falling back to the filename.
    public func parsePage(_ raw: String, filename: String) throws -> (page: Page, body: String) {
        let (yaml, body) = split(raw)
        guard let yaml else {
            throw OverprintError.postValidation(file: filename, issues: ["missing frontmatter block (file must start with ---)"])
        }

        let loaded: Any?
        do {
            loaded = try Yams.load(yaml: yaml)
        } catch {
            throw OverprintError.postValidation(file: filename, issues: ["invalid YAML frontmatter: \(error)"])
        }
        guard let dict = loaded as? [String: Any] else {
            throw OverprintError.postValidation(file: filename, issues: ["frontmatter is not a key/value mapping"])
        }

        let title = (dict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title, !title.isEmpty else {
            throw OverprintError.postValidation(file: filename, issues: ["missing required field: title"])
        }

        let slugField = (dict["slug"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = (slugField?.isEmpty == false) ? slugField! : Self.slug(fromFilename: filename)
        if let issue = Self.slugIssue(slug) {
            throw OverprintError.postValidation(file: filename, issues: [issue])
        }
        let draft = (dict["draft"] as? Bool) ?? false

        return (Page(title: title, slug: slug, draft: draft,
                     description: Self.optionalString(dict["description"])), body)
    }

    /// Rejects a slug that could escape the output directory or collide with the filesystem.
    ///
    /// The slug becomes an output filename (`<slug>.html`), and `appendingPathComponent` does not
    /// reject `..`, so an unchecked slug like `../../notes` writes outside `dist/` and can overwrite
    /// an arbitrary file. Returns a validation issue, or nil when the slug is safe.
    static func slugIssue(_ slug: String) -> String? {
        guard !slug.isEmpty else { return "slug cannot be empty" }
        guard slug != "." && slug != ".." else { return "slug \"\(slug)\" is not a valid filename" }
        guard !slug.contains("/") && !slug.contains("\\") else {
            return "slug \"\(slug)\" cannot contain a path separator"
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard slug.unicodeScalars.allSatisfy(allowed.contains) else {
            return "slug \"\(slug)\" may only contain letters, numbers, dots, hyphens, and underscores"
        }
        return nil
    }

    /// Derives a slug from `YYYY-MM-DD-slug.md` by stripping the date prefix and extension.
    /// Reports a post filename whose `YYYY-MM-DD-` prefix disagrees with its `date` field.
    ///
    /// The two are a documented pair: the prefix is how posts sort on disk and how a human finds a
    /// post's file, while `date` is what the site publishes. Nothing keeps them in step
    /// automatically, so a date edited in one place and not the other goes unnoticed until the
    /// published order looks wrong.
    ///
    /// Returns nil when they agree, and also when the filename carries no date prefix at all: that
    /// is a different (and looser) convention question, and flagging it would fail sites that build
    /// correctly today.
    static func filenameDateIssue(filename: String, date: Date) -> String? {
        guard let range = filename.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) else {
            return nil
        }
        let fromFilename = String(filename[range])
        let fromFrontmatter = DateFormat.isoString(date)
        guard fromFilename != fromFrontmatter else { return nil }
        return "filename starts with \(fromFilename) but the date field is \(fromFrontmatter); "
            + "rename the file or change the date so they match"
    }

    static func slug(fromFilename filename: String) -> String {
        var name = filename
        if name.hasSuffix(".md") { name.removeLast(3) }
        if let r = name.range(of: #"^\d{4}-\d{2}-\d{2}-"#, options: .regularExpression) {
            name = String(name[r.upperBound...])
        }
        return name
    }

    /// Accepts a YAML list of strings, or a comma-separated string, as tags.
    /// An optional free-text field. A wrong type is ignored rather than reported, matching how
    /// `tags` and `draft` already tolerate one.
    static func optionalString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func stringArray(_ value: Any?) -> [String] {
        if let array = value as? [Any] {
            return array.compactMap { $0 as? String }
        }
        if let string = value as? String {
            return string.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        return []
    }
}
