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
        let store = SiteStore(siteURL: siteURL)
        let issues = store.validate()

        // Say what the site overrides. An override that silently stops applying, or one you forgot
        // you made, is hard to spot from the output alone.
        let overrides = store.themeOverrides()
        if !overrides.isEmpty {
            print("Theme overrides: \(overrides.joined(separator: ", "))")
        }

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
