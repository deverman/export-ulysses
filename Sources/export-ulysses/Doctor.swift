import ArgumentParser
import Foundation
import UlyssesExporter

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Verify format compatibility and preview a migration without writing notes."
    )

    @Option(help: "Optional output folder to check for safety, capacity, and writability.")
    var output: String?

    @OptionGroup var options: BackupOptions

    func run() async throws {
        let input = try options.resolvedBackup()
        let destination = output.map { NSString(string: $0).expandingTildeInPath }
        print("Using Ulysses backup: \(input)")
        let result = await options.exporter().doctor(
            input: input,
            output: destination,
            allowUnknownFormat: options.allowUnknownFormat,
            commandLine: CommandLine.arguments
        )
        CLIOutput.printPreflight(result)
        guard !result.hasFailures else { throw ExitCode.failure }
        if let analysis = result.analysis {
            print("")
            CLIOutput.printSummary(analysis.summary, includePrivateDetails: false)
            print("")
            print("Anonymous support report JSON:")
            print(analysis.supportJSON)
        }
    }
}
