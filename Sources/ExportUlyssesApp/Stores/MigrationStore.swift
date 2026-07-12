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
    private var backupAccess: SecurityScopedAccess?
    private var destinationAccess: SecurityScopedAccess?

    var supportsAutomaticBackupDiscovery: Bool {
        AppDistribution.supportsAutomaticBackupDiscovery
    }

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
        if AppDistribution.isAppStore {
            restoreAppStoreSelections()
        } else {
            discoverBackup()
        }
    }

    func discoverBackup() {
        guard supportsAutomaticBackupDiscovery else { return }
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
        backupAccess = SecurityScopedAccess(url: url)
        if AppDistribution.isAppStore {
            try? SecurityScopedBookmarkStore.save(url, key: .backup, readOnly: true)
        }
        backupPath = url.path
        resetResults()
    }

    func chooseDestination() {
        guard let selection = PanelService.chooseDestination() else { return }
        destinationAccess = SecurityScopedAccess(url: selection.parent)
        if AppDistribution.isAppStore {
            try? SecurityScopedBookmarkStore.save(selection.parent, key: .destinationParent, readOnly: false)
        }
        destinationPath = selection.destination.path
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

    func useSampleBackup() {
        do {
            backupAccess = nil
            backupPath = try SampleBackupFactory.create().path
            resetResults()
        } catch {
            errorMessage = error.localizedDescription
            phase = .failed
        }
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

    private func restoreAppStoreSelections() {
        if let backup = SecurityScopedBookmarkStore.restore(.backup) {
            backupAccess = SecurityScopedAccess(url: backup)
            backupPath = backup.path
        } else {
            backupPath = ""
        }
        if let parent = SecurityScopedBookmarkStore.restore(.destinationParent) {
            destinationAccess = SecurityScopedAccess(url: parent)
            destinationPath = parent.appendingPathComponent("FSNotes Ulysses Migration", isDirectory: true).path
        } else {
            destinationPath = ""
        }
        resetResults()
    }
}
