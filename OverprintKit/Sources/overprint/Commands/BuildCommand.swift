import ArgumentParser
import Foundation
import OverprintKit

struct BuildCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build the site into dist/."
    )

    @Argument(help: "Path to the site folder.")
    var path: String = "."

    @Flag(name: .long, help: "Include posts marked draft: true. Off by default, so what you build is what you can publish.")
    var drafts: Bool = false

    func run() async throws {
        let siteURL = URL(fileURLWithPath: path, isDirectory: true)
        let summary = try SiteBuilder().build(siteURL: siteURL, includeDrafts: drafts)
        let noun = summary.postCount == 1 ? "post" : "posts"
        print("Built \(summary.postCount) \(noun) into \(summary.outputURL.path)")
    }
}
