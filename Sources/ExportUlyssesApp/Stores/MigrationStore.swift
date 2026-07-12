import Foundation
import Observation
import UlyssesExporter

@MainActor
@Observable
final class MigrationStore {
    var backupPath = ""
    var destinationPath = ""
    var phase: MigrationPhase = .configuring
    var checks: [PreflightCheck] = []
    var summary: ExportSummary?
    var supportJSON = ""
    var progress = MigrationProgress()
    var errorMessage: String?

    var isWorking: Bool {
        phase == .checking || phase == .migrating
    }

    var canCheck: Bool {
        !backupPath.isEmpty && !destinationPath.isEmpty && !isWorking
    }

    var canMigrate: Bool {
        phase == .ready && checks.allSatisfy { $0.status != .failure }
    }

    init() {
        destinationPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/FSNotes Ulysses Migration", isDirectory: true).path
        discoverBackup()
    }

    func discoverBackup() {
        do {
            backupPath = try UlyssesBackupLocator().newestBackup().path
            resetResults()
        } catch {
            backupPath = ""
            errorMessage = error.localizedDescription
        }
    }

    func chooseBackup() {
        guard let url = PanelService.chooseBackup() else { return }
        backupPath = url.path
        resetResults()
    }

    func chooseDestination() {
        guard let url = PanelService.chooseDestination() else { return }
        destinationPath = url.path
        resetResults()
    }

    func runPreflight() {
        guard canCheck else { return }
        phase = .checking
        checks = []
        summary = nil
        supportJSON = ""
        errorMessage = nil
        progress = MigrationProgress(phase: "Inspecting backup")
        let worker = exporter()

        Task {
            let result = await worker.doctor(
                input: backupPath,
                output: destinationPath,
                commandLine: ["Export Ulysses", "doctor"]
            )
            checks = result.checks
            summary = result.analysis?.summary
            supportJSON = result.analysis?.supportJSON ?? ""
            progress = MigrationProgress()
            phase = result.hasFailures ? .failed : .ready
            if result.hasFailures {
                errorMessage = result.checks.first(where: { $0.status == .failure })?.message
            }
        }
    }

    func migrate() {
        guard canMigrate else { return }
        phase = .migrating
        errorMessage = nil
        progress = MigrationProgress(phase: "Preparing migration")
        let worker = exporter()

        Task {
            do {
                summary = try await worker.run(
                    input: backupPath,
                    output: destinationPath,
                    commandLine: ["Export Ulysses", "migrate"]
                )
                progress = MigrationProgress()
                phase = .complete
            } catch {
                progress = MigrationProgress()
                errorMessage = error.localizedDescription
                phase = .failed
            }
        }
    }

    func revealExport() {
        WorkspaceService.reveal(destinationPath)
    }

    func openFSNotes() {
        WorkspaceService.openFSNotes()
    }

    func openFullDiskAccess() {
        WorkspaceService.openFullDiskAccess()
    }

    func saveSupportReport() {
        guard !supportJSON.isEmpty else { return }
        do {
            try PanelService.saveSupportReport(supportJSON)
        } catch {
            errorMessage = error.localizedDescription
            phase = .failed
        }
    }

    private func exporter() -> Exporter {
        Exporter(maxConcurrentExports: 2) { [weak self] update in
            Task { @MainActor [weak self] in
                self?.progress = MigrationProgress(
                    phase: update.phase,
                    completed: update.completed,
                    total: update.total
                )
            }
        }
    }

    private func resetResults() {
        phase = .configuring
        checks = []
        summary = nil
        supportJSON = ""
        errorMessage = nil
        progress = MigrationProgress()
    }
}
