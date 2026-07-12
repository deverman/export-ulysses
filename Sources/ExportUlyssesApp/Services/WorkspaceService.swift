import AppKit

@MainActor
enum WorkspaceService {
    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    static func openFSNotes() {
        let workspace = NSWorkspace.shared
        let identifiers = ["co.fluder.FSNotes", "com.fsnotes.FSNotes"]
        if let appURL = identifiers.compactMap({ workspace.urlForApplication(withBundleIdentifier: $0) }).first {
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.openApplication(at: appURL, configuration: configuration)
            return
        }
        workspace.open(URL(fileURLWithPath: "/Applications/FSNotes.app"))
    }

    static func openFullDiskAccess() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }
}
