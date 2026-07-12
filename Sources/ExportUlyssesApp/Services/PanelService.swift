import AppKit
import UniformTypeIdentifiers

@MainActor
enum PanelService {
    struct DestinationSelection {
        let destination: URL
        let parent: URL
    }

    static func chooseBackup() -> URL? {
        while true {
            let panel = NSOpenPanel()
            panel.title = "Choose a Ulysses Backup"
            panel.message = "Select a .ulbackup package. In Ulysses, use File > Browse Backups and Reveal in Finder to locate one."
            panel.prompt = "Choose Backup"
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowsMultipleSelection = false
            panel.treatsFilePackagesAsDirectories = false

            // Ulysses' package type is not registered consistently outside its process.
            // Filtering by a synthesized UTType disables valid .ulbackup packages.
            guard panel.runModal() == .OK, let url = panel.url else { return nil }
            if url.pathExtension.caseInsensitiveCompare("ulbackup") == .orderedSame {
                return url
            }

            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "That is not a Ulysses backup"
            alert.informativeText = "Choose a package whose name ends in .ulbackup."
            alert.addButton(withTitle: "Choose Again")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() != .alertFirstButtonReturn { return nil }
        }
    }

    static func chooseDestination() -> DestinationSelection? {
        let panel = NSOpenPanel()
        panel.title = "Choose the Parent Folder"
        panel.message = "A new FSNotes Ulysses Migration folder will be created here."
        panel.prompt = "Choose Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let parent = panel.url else { return nil }
        return DestinationSelection(
            destination: parent.appendingPathComponent("FSNotes Ulysses Migration", isDirectory: true),
            parent: parent
        )
    }

    static func saveSupportReport(_ report: String) throws {
        let panel = NSSavePanel()
        panel.title = "Save Anonymous Support Report"
        panel.nameFieldStringValue = "ulysses-export-report.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try report.write(to: url, atomically: true, encoding: .utf8)
    }
}
