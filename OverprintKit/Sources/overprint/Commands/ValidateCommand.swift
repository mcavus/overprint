import ArgumentParser
import Foundation
import OverprintKit

struct ValidateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate overprint.yml and every post and page against the contract."
    )

    @Argument(help: "Path to the site folder.")
    var path: String = "."

    func run() async throws {
        let siteURL = URL(fileURLWithPath: path, isDirectory: true)
        let issues = SiteStore(siteURL: siteURL).validate()

        guard issues.isEmpty else {
            for issue in issues {
                FileHandle.standardError.write(Data((issue.description + "\n").utf8))
            }
            let noun = issues.count == 1 ? "problem" : "problems"
            FileHandle.standardError.write(Data("\(issues.count) \(noun) found.\n".utf8))
            throw ExitCode.failure
        }

        print("Site is valid.")
    }
}
