import ArgumentParser
import Foundation
import OverprintKit

struct InitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Scaffold a new Overprint site in a folder."
    )

    @Argument(help: "Path to the new site folder.")
    var path: String = "."

    @Option(name: .shortAndLong, help: "Site title.")
    var title: String = "My Site"

    func run() async throws {
        let siteURL = URL(fileURLWithPath: path, isDirectory: true)
        try SiteScaffolder().scaffold(at: siteURL, title: title)
        print("Scaffolded a new site at \(siteURL.path)")
    }
}
