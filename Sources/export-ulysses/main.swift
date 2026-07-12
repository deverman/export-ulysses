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

    @Argument(help: "The folder where FSNotes TextBundles should be written. Required for export; optional with --analyze or --doctor.")
    var output: String?

    @Flag(help: "Create directories for each Ulysses Group, and export notes into them.")
    var keepGroups = false

    @Flag(name: .shortAndLong, help: "Log export activity and debugging statements.")
    var verbose = false

    @Option(name: .long, parsing: .upToNextOption, help: "Groups to ignore on export.")
    var ignore: [String] = []

    @Option(help: "Maximum number of sheets to export concurrently.")
    var jobs = 2

    @Flag(help: "Scan the backup and print a privacy-safe migration report without writing TextBundles.")
    var analyze = false

    @Flag(help: "Run preflight checks for the backup, output folder, FSNotes TextBundle compatibility, and asset references.")
    var doctor = false

    func run() async throws {
        let exporter = Exporter(verbose: verbose, maxConcurrentExports: jobs)

        if doctor {
            let result = await exporter.doctor(
                input: input,
                output: output,
                keepGroups: keepGroups,
                ignoring: ignore,
                commandLine: CommandLine.arguments
            )
            printPreflight(result)
            if result.hasFailures {
                throw ExitCode.failure
            }
            if analyze, let analysis = result.analysis {
                printAnalysis(analysis)
            }
            return
        }

        if analyze {
            print("Analyzing Ulysses backup for FSNotes migration...")
            let analysis = try await exporter.analyze(
                input: input,
                keepGroups: keepGroups,
                ignoring: ignore,
                commandLine: CommandLine.arguments
            )
            printAnalysis(analysis)
            return
        }

        guard let output else {
            throw ValidationError("Missing expected argument '<output>'. Provide an output folder, or use --analyze to scan without writing.")
        }

        print("Starting FSNotes export from Ulysses backup...")
        let summary = try await exporter
            .run(input: input, output: output, keepGroups: keepGroups, ignoring: ignore, commandLine: CommandLine.arguments)
        printSummary(summary)
        print("Wrote migration notes under _Ulysses Migration and support files under hidden .export-ulysses.")
    }

    private func printAnalysis(_ analysis: ExportAnalysis) {
        printSummary(analysis.summary)
        print("")
        print("Privacy-safe support report JSON:")
        print(analysis.supportJSON)
    }

    private func printSummary(_ summary: ExportSummary) {
        print("""
        Exported \(summary.sheets) sheets.
        Sidebar notes: \(summary.sidebarNotes)
        Sidebar file attachments: \(summary.fileAttachments)
        Inline images: \(summary.inlineImages)
        Keywords: \(summary.keywords)
        Material sheets: \(summary.materialSheets)
        Glued sheets: \(summary.gluedSheets)
        Archive sheets: \(summary.archiveSheets)
        Template sheets: \(summary.templateSheets)
        Trash sheets: \(summary.trashSheets)
        Favorite sheets: \(summary.favoriteSheets)
        Saved filters: \(summary.savedFilters)
        Sheet order notes: \(summary.orderNotes)
        Group metadata notes: \(summary.metadataNotes)
        Export report notes: \(summary.reportNotes)
        Duplicate note titles renamed: \(summary.duplicateTitles)
        Missing media references: \(summary.missingMedia)
        Recovered media references: \(summary.recoveredMedia)
        Unsupported XML nodes: \(summary.unsupportedNodes)
        """)

        if !summary.missingMediaDetails.isEmpty {
            print("Missing media detail:")
            for (key, count) in summary.missingMediaDetails.sorted(by: { $0.key < $1.key }) {
                print("- \(key): \(count)")
            }
        }
        if !summary.unsupportedDetails.isEmpty {
            print("Unsupported XML detail:")
            for (key, count) in summary.unsupportedDetails.sorted(by: { $0.key < $1.key }) {
                print("- \(key): \(count)")
            }
        }
    }

    private func printPreflight(_ result: PreflightResult) {
        print("Preflight checks:")
        for check in result.checks {
            let prefix: String
            switch check.status {
            case .success:
                prefix = "OK"
            case .warning:
                prefix = "WARN"
            case .failure:
                prefix = "FAIL"
            }
            print("[\(prefix)] \(check.name): \(check.message)")
        }
    }
}
