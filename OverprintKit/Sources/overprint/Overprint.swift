import ArgumentParser
import OverprintKit

/// Root command for the `overprint` CLI, a thin front-end over OverprintKit.
@main
struct OverprintCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "overprint",
        abstract: "Build, preview, and manage an Overprint blog from the command line.",
        version: Overprint.version,
        subcommands: [
            InitCommand.self,
            NewCommand.self,
            BuildCommand.self,
            ServeCommand.self,
            ValidateCommand.self,
        ]
    )
}
