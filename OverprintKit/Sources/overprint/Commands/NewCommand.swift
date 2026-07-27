import ArgumentParser
import Foundation
import OverprintKit

struct NewCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: "Create a new post draft."
    )

    @Argument(help: "Title of the new post.")
    var title: String

    @Option(name: .shortAndLong, help: "Path to the site folder.")
    var site: String = "."

    func run() async throws {
        let siteURL = URL(fileURLWithPath: site, isDirectory: true)
        let fileURL = try PostWriter().createPost(in: siteURL, title: title)
        print("Created \(fileURL.path)")
    }
}
