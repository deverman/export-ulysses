import ArgumentParser
import Foundation
import UlyssesExporter

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
