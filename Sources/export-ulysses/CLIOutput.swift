import UlyssesExporter

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
