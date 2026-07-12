import ArgumentParser
import Foundation
import UlyssesExporter

struct Migrate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create a new, validated FSNotes library from Ulysses."
    )

    @Argument(help: "New output folder. Place it inside an existing FSNotes storage or use it as a new Default Storage.")
    var output: String

    @OptionGroup var options: BackupOptions

    func run() async throws {
        let input = try options.resolvedBackup()
        let destination = NSString(string: output).expandingTildeInPath
        print("Using Ulysses backup: \(input)")
        print("Starting validated FSNotes migration...")
        let summary = try await options.exporter().run(
            input: input,
            output: destination,
            allowUnknownFormat: options.allowUnknownFormat,
            commandLine: CommandLine.arguments
        )
        CLIOutput.printSummary(summary)
        print("Validation passed. Migration notes are under _Ulysses Migration; anonymous diagnostics are under hidden .export-ulysses.")
        let outputURL = URL(fileURLWithPath: destination).standardizedFileURL
        print("If FSNotes already has notes, keep its current Default Storage and place this migration folder inside it.")
        print("For a new FSNotes library, set Default Storage to \(outputURL.path).")
        if summary.trashSheets > 0 {
            print("Ulysses Trash was exported to \(outputURL.appendingPathComponent("Trash").path).")
            print("For an existing library, move those TextBundles into FSNotes' currently configured Trash; for a new library, configure FSNotes Trash to use that folder.")
        }
    }
}
