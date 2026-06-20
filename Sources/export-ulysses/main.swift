import ArgumentParser
import Foundation
import UlyssesExporter

@main
struct ExportUlysses: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export-ulysses",
        abstract: "Export a Ulysses backup to FSNotes-readable TextBundles."
    )

    @Argument(help: "The path to a Ulysses .ulbackup folder, for example Ulysses/Backups/Latest Backup.ulbackup.")
    var input: String

    @Argument(help: "The folder where FSNotes TextBundles should be written.")
    var output: String

    @Flag(help: "Create directories for each Ulysses Group, and export notes into them.")
    var keepGroups = false

    @Flag(name: .shortAndLong, help: "Log export activity and debugging statements.")
    var verbose = false

    @Option(name: .long, parsing: .upToNextOption, help: "Groups to ignore on export.")
    var ignore: [String] = []

    @Option(help: "Maximum number of sheets to export concurrently.")
    var jobs = 2

    func run() async throws {
        print("Starting FSNotes export from Ulysses backup...")
        let summary = try await Exporter(verbose: verbose, maxConcurrentExports: jobs)
            .run(input: input, output: output, keepGroups: keepGroups, ignoring: ignore)

        print("""
        Exported \(summary.sheets) sheets.
        Sidebar notes: \(summary.sidebarNotes)
        Sidebar file attachments: \(summary.fileAttachments)
        Inline images: \(summary.inlineImages)
        Keywords: \(summary.keywords)
        Missing media references: \(summary.missingMedia)
        Unsupported XML nodes: \(summary.unsupportedNodes)
        """)

        if !summary.unsupportedDetails.isEmpty {
            print("Unsupported XML detail:")
            for (key, count) in summary.unsupportedDetails.sorted(by: { $0.value > $1.value }) {
                print("- \(key): \(count)")
            }
        }
    }
}
