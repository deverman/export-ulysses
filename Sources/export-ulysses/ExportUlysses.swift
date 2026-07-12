import ArgumentParser
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
