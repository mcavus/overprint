import Foundation

/// Reads a site folder (the single source of truth): its `overprint.yml` config and the
/// Markdown posts under `content/posts`.
public struct SiteStore {
    public let siteURL: URL

    public init(siteURL: URL) {
        self.siteURL = siteURL
    }

    public var configURL: URL { siteURL.appendingPathComponent("overprint.yml") }
    public var postsDirURL: URL { siteURL.appendingPathComponent("content/posts") }
    public var pagesDirURL: URL { siteURL.appendingPathComponent("content/pages") }

    public func loadConfig() throws -> SiteConfig {
        try SiteConfig.load(from: configURL)
    }

    /// Loads every `.md` post, sorted newest first. Throws on the first invalid post.
    public func loadPosts() throws -> [LoadedPost] {
        let parser = FrontmatterParser()
        var posts: [LoadedPost] = []
        for url in markdownFiles() {
            let raw: String
            do {
                raw = try String(contentsOf: url, encoding: .utf8)
            } catch {
                throw OverprintError.io("\(url.lastPathComponent): \(error.localizedDescription)")
            }
            let (post, body) = try parser.parse(raw, filename: url.lastPathComponent)
            posts.append(LoadedPost(post: post, body: body, sourceURL: url))
        }
        posts.sort { $0.post.date > $1.post.date }
        return posts
    }

    /// Loads every standalone page under `content/pages`, sorted by slug. Returns an empty
    /// array when the folder does not exist, so pages stay entirely optional.
    public func loadPages() throws -> [LoadedPage] {
        let parser = FrontmatterParser()
        var pages: [LoadedPage] = []
        for url in markdownFiles(in: pagesDirURL) {
            let raw: String
            do {
                raw = try String(contentsOf: url, encoding: .utf8)
            } catch {
                throw OverprintError.io("\(url.lastPathComponent): \(error.localizedDescription)")
            }
            let (page, body) = try parser.parsePage(raw, filename: url.lastPathComponent)
            pages.append(LoadedPage(page: page, body: body, sourceURL: url))
        }
        pages.sort { $0.page.slug < $1.page.slug }
        return pages
    }

    /// Files this site overrides from the bundled theme, for `overprint validate` to report.
    /// Empty when the site uses the bundled theme as-is.
    public func themeOverrides() -> [String] {
        ((try? Theme.load(siteURL: siteURL))?.overriddenNames) ?? []
    }

    /// Checks the site's `theme/` directory: unknown template names, and whether a vendored
    /// `base.html` still carries the blocks the rest of the engine depends on.
    func themeErrors() -> [OverprintError] {
        var errors: [OverprintError] = []
        let templatesDir = siteURL.appendingPathComponent("theme/templates")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: templatesDir.path)) ?? []

        for name in names.sorted() where !name.hasPrefix(".") {
            if let issue = Theme.templateNameIssue(name) {
                errors.append(issue)
                continue
            }
            guard name == "base.html",
                  let body = try? String(contentsOf: templatesDir.appendingPathComponent(name), encoding: .utf8)
            else { continue }
            for requirement in Theme.baseRequirements where !body.contains(requirement.needle) {
                errors.append(.templateError(
                    "theme/templates/base.html is missing \(requirement.needle): \(requirement.why)."
                ))
            }
        }
        return errors
    }

    /// A non-throwing validation pass that returns every issue found: the theme overrides, the
    /// config, and every post and page.
    public func validate() -> [OverprintError] {
        var errors: [OverprintError] = []
        errors.append(contentsOf: themeErrors())
        do {
            _ = try loadConfig()
        } catch let error as OverprintError {
            errors.append(error)
        } catch {
            errors.append(.io(error.localizedDescription))
        }

        let parser = FrontmatterParser()
        // Posts and pages both render to `<slug>.html`, so a repeated slug means one silently
        // overwrites the other in the output. Track slugs across both to catch that.
        var slugOwners: [String: String] = [:]

        func claim(slug: String, file: String) {
            if let existing = slugOwners[slug] {
                errors.append(.postValidation(
                    file: file,
                    issues: ["slug \"\(slug)\" is already used by \(existing); slugs become <slug>.html and must be unique"]
                ))
            } else {
                slugOwners[slug] = file
            }
        }

        for url in markdownFiles(in: postsDirURL) {
            do {
                let raw = try String(contentsOf: url, encoding: .utf8)
                let (post, _) = try parser.parse(raw, filename: url.lastPathComponent)
                claim(slug: post.slug, file: url.lastPathComponent)
                if let issue = FrontmatterParser.filenameDateIssue(
                    filename: url.lastPathComponent, date: post.date
                ) {
                    errors.append(.postValidation(file: url.lastPathComponent, issues: [issue]))
                }
            } catch let error as OverprintError {
                errors.append(error)
            } catch {
                errors.append(.io("\(url.lastPathComponent): \(error.localizedDescription)"))
            }
        }

        for url in markdownFiles(in: pagesDirURL) {
            do {
                let raw = try String(contentsOf: url, encoding: .utf8)
                let (page, _) = try parser.parsePage(raw, filename: url.lastPathComponent)
                claim(slug: page.slug, file: url.lastPathComponent)
            } catch let error as OverprintError {
                errors.append(error)
            } catch {
                errors.append(.io("\(url.lastPathComponent): \(error.localizedDescription)"))
            }
        }
        return errors
    }

    private func markdownFiles() -> [URL] {
        markdownFiles(in: postsDirURL)
    }

    private func markdownFiles(in directory: URL) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return entries
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
