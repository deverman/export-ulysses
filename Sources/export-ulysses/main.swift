import ArgumentParser
import Foundation
import UlyssesExporter

@main
struct ExportUlysses: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export-ulysses",
        abstract: "Migrate a Ulysses backup to an FSNotes library.",
        version: ExportUlyssesVersion.current,
        subcommands: [Migrate.self, Doctor.self]
    )
}

struct BackupOptions: ParsableArguments {
    @Option(help: "Ulysses .ulbackup path. Defaults to the newest local Ulysses backup.")
    var backup: String?

    @Option(help: "Maximum sheets processed concurrently.")
    var jobs = 2

    @Flag(name: .shortAndLong, help: "Print detailed progress.")
    var verbose = false

    @Flag(help: "Developer override for an unverified Ulysses format. The result may be incomplete.")
    var allowUnknownFormat = false

    func resolvedBackup() throws -> String {
        if let backup { return NSString(string: backup).expandingTildeInPath }
        return try UlyssesBackupLocator().newestBackup().path
    }

    func exporter() -> Exporter {
        Exporter(verbose: verbose, maxConcurrentExports: jobs) { update in
            print("\(update.phase): \(update.completed)/\(update.total)")
        }
    }
}

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

enum CLIOutput {
    static func printSummary(_ summary: ExportSummary, includePrivateDetails: Bool = true) {
        print("""
        Sheets: \(summary.sheets)
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
        Duplicate note titles renamed: \(summary.duplicateTitles)
        Missing media references: \(summary.missingMedia)
        Recovered media references: \(summary.recoveredMedia)
        Unsupported cosmetic XML nodes: \(summary.unsupportedNodes)
        """)
        guard includePrivateDetails else { return }
        if !summary.missingMediaDetails.isEmpty {
            print("Missing media detail is available in _Ulysses Migration/Ulysses Export Report.")
        }
    }

    static func printPreflight(_ result: PreflightResult) {
        print("Preflight checks:")
        for check in result.checks {
            let prefix = switch check.status {
            case .success: "OK"
            case .warning: "WARN"
            case .failure: "FAIL"
            }
            print("[\(prefix)] \(check.name): \(check.message)")
        }
    }
}
