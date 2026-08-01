import Foundation
import Swifter

/// A tiny static file server for previewing a built site (`dist/`). Wraps Swifter, and is
/// shared by the CLI `serve` command and the app's ServerManager. It resolves every request
/// path against the served directory (so nested paths like `assets/style.css` work) and
/// serves each file with a correct content type.
public final class PreviewServer {
    private var server: HttpServer?
    public private(set) var port: Int = 0

    public init() {}

    public var isRunning: Bool { server?.operating ?? false }

    public var url: URL? {
        guard isRunning else { return nil }
        return URL(string: "http://localhost:\(port)/")
    }

    /// Serves `directory` (a built `dist/`). Tries `requestedPort`, falling back to an
    /// OS-assigned free port if it is taken. Returns the port actually bound.
    @discardableResult
    public func start(directory: URL, port requestedPort: Int = 4321) throws -> Int {
        stop()

        guard (0...65535).contains(requestedPort) else {
            throw OverprintError.io("port \(requestedPort) is out of range (0-65535)")
        }

        let base = directory.standardizedFileURL
        let http = HttpServer()
        // Bind loopback only. Without this Swifter listens on 0.0.0.0, which would put the preview
        // (including unpublished drafts, since previews build with includeDrafts: true) on the
        // local network for anyone on the same Wi-Fi.
        http.listenAddressIPv4 = "127.0.0.1"
        http.notFoundHandler = { request in
            PreviewServer.response(for: request.path, base: base)
        }

        do {
            try http.start(in_port_t(requestedPort), forceIPv4: true)
        } catch {
            try http.start(0, forceIPv4: true)
        }
        port = (try? http.port()) ?? requestedPort
        server = http
        return port
    }

    public func stop() {
        server?.stop()
        server = nil
        port = 0
    }

    static func response(for requestPath: String, base: URL) -> HttpResponse {
        var relative = requestPath.components(separatedBy: "?").first ?? requestPath
        while relative.hasPrefix("/") { relative.removeFirst() }
        if relative.isEmpty {
            relative = "index.html"
        } else if relative.hasSuffix("/") {
            relative += "index.html"
        }

        let fileURL = base.appendingPathComponent(relative).standardizedFileURL
        // Refuse to serve anything outside the served directory.
        guard fileURL.path == base.path || fileURL.path.hasPrefix(base.path + "/") else {
            return .forbidden
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              let data = FileManager.default.contents(atPath: fileURL.path)
        else {
            return notFoundResponse(base: base)
        }

        let contentType = mimeType(forExtension: fileURL.pathExtension)
        return .raw(200, "OK", ["Content-Type": contentType], { writer in
            try? writer.write(data)
        })
    }

    /// The site's own 404 page, so a missing address previews the way the host will serve it.
    ///
    /// The status stays 404: a preview that answered 200 would hide a broken link rather than show
    /// it. Falls back to a bare 404 when the build has not produced the page yet.
    static func notFoundResponse(base: URL) -> HttpResponse {
        let page = base.appendingPathComponent("404.html")
        guard let data = FileManager.default.contents(atPath: page.path) else { return .notFound }
        return .raw(404, "Not Found", ["Content-Type": mimeType(forExtension: "html")], { writer in
            try? writer.write(data)
        })
    }

    static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "ico": return "image/x-icon"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "ttf": return "font/ttf"
        case "xml": return "application/xml; charset=utf-8"
        case "txt", "md": return "text/plain; charset=utf-8"
        default: return "application/octet-stream"
        }
    }
}
