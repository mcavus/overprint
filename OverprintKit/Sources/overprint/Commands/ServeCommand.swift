import ArgumentParser
import Foundation
import OverprintKit

struct ServeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Build the site and serve it locally for preview."
    )

    @Argument(help: "Path to the site folder.")
    var path: String = "."

    @Option(name: .shortAndLong, help: "Port to serve on.")
    var port: Int = 4321

    func run() async throws {
        let siteURL = URL(fileURLWithPath: path, isDirectory: true)
        // Preview is for the author, so it shows drafts.
        let summary = try SiteBuilder().build(siteURL: siteURL, includeDrafts: true)

        let server = PreviewServer()
        let boundPort = try server.start(directory: summary.outputURL, port: port)
        let noun = summary.postCount == 1 ? "post" : "posts"
        print("Serving \(summary.postCount) \(noun) at http://localhost:\(boundPort)/  (press Ctrl-C to stop)")

        while !Task.isCancelled {
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        server.stop()
    }
}
