import Foundation

struct ExportReportWriter {
    let outputURL: URL

    func writeReport(summary: ExportSummary, snapshot: UlyssesLibrarySnapshot, commandLine: [String]) throws {
        let dates = SheetDates(created: Date(), modified: Date())
        _ = try TextBundleWriter().writeBundle(
            named: "Ulysses Export Report",
            markdown: reportMarkdown(summary: summary, snapshot: snapshot, commandLine: commandLine),
            in: outputURL.appendingPathComponent("_Ulysses Migration", isDirectory: true),
            dates: dates
        )
        let supportDirectory = outputURL.appendingPathComponent(".export-ulysses", isDirectory: true)
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try supportJSON(summary: summary, snapshot: snapshot, commandLine: commandLine)
            .write(to: supportDirectory.appendingPathComponent("ulysses-export-report.json"), atomically: true, encoding: .utf8)
    }

    func reportMarkdown(summary: ExportSummary, snapshot: UlyssesLibrarySnapshot, commandLine: [String]) -> String {
        var lines = [
            "# Ulysses Export Report",
            "",
            "#ulysses/export-report",
            "",
            "## Summary",
            "",
            "- Sheets: \(summary.sheets)",
            "- Ulysses sheet notes: \(summary.sidebarNotes)",
            "- Sidebar file attachments: \(summary.fileAttachments)",
            "- Inline images: \(summary.inlineImages)",
            "- Keywords: \(summary.keywords)",
            "- Material sheets: \(summary.materialSheets)",
            "- Glued sheets: \(summary.gluedSheets)",
            "- Archive sheets: \(summary.archiveSheets)",
            "- Template sheets: \(summary.templateSheets)",
            "- Trash sheets: \(summary.trashSheets)",
            "- Favorite sheets: \(summary.favoriteSheets)",
            "- Saved filters: \(summary.savedFilters)",
            "- Sheet order notes: \(summary.orderNotes)",
            "- Group metadata notes: \(summary.metadataNotes)",
            "- Duplicate note titles renamed: \(summary.duplicateTitles)",
            "- Missing media references: \(summary.missingMedia)",
            "- Recovered media references: \(summary.recoveredMedia)",
            "- Unsupported XML nodes: \(summary.unsupportedNodes)",
            "",
            "## What Was Preserved",
            "",
            "- Sheet body text and Markdown-compatible formatting",
            "- Inline images and file attachments when the source asset was present",
            "- Ulysses sidebar notes, comments, annotations, keywords, favorites, saved filters, material status, glued sheet status, archive/template/trash role, and group metadata as visible Markdown",
            "- TextBundle `info.json` dates for FSNotes",
            "",
            "## Where Notes, Comments, And Annotations Went",
            "",
            "- Sheet notes: appended to the same exported note under `## Ulysses Sidebar Notes`, with each note numbered.",
            "- Inline comments: kept at their original text positions as `**[Ulysses comment: ...]**`.",
            "- Comment paragraphs: kept at their original positions as `> **Ulysses comment:** ...` blockquotes.",
            "- Annotations: annotated text stays in place and the annotation follows as `**[Ulysses annotation: ...]**`.",
            "- Glued sheets: exported as separate TextBundles. If Ulysses displayed their notes and annotations together, use `Ulysses Library Map` to find every sheet in that glued cluster.",
            "",
            "## What FSNotes Cannot Model Directly",
            "",
            "- Ulysses inspector/sidebar UI placement",
            "- Ulysses group icons, colors, goals, and activity tracking as native FSNotes folder settings",
            "- Ulysses favorites as native FSNotes pins; favorites are tagged and listed in the migration companion instead",
            "",
            "## Finish In FSNotes",
            "",
            "### Existing FSNotes Library",
            "",
            "1. Keep the current Default Storage. With FSNotes closed, place the complete export folder inside it, or add the export as an external folder for review.",
            "2. In FSNotes Settings > Advanced, verify the existing Trash location. Move the TextBundles inside `<export folder>/Trash` into that configured folder if you want the \(summary.trashSheets) Ulysses Trash sheets to appear in FSNotes Trash.",
            "3. Restart FSNotes and verify the imported folder before deleting the separate export or backup.",
            "",
            "### New Or Empty FSNotes Library",
            "",
            "1. In FSNotes Settings > General, select the export folder as Default Storage.",
            "2. In Settings > Advanced, set Trash to `<export folder>/Trash`.",
            "3. Restart FSNotes and confirm that Ulysses Inbox sheets appear in Inbox and deleted Ulysses sheets appear in Trash.",
            "",
            "Warning: FSNotes Empty Trash permanently deletes the imported Ulysses Trash sheets.",
            "",
            "## Support File",
            "",
            "A privacy-safe JSON support report and a complete migration manifest were written to `.export-ulysses/`. FSNotes should not show that hidden folder in the note list.",
            "",
            "All migration-only notes are grouped under `_Ulysses Migration`. In FSNotes, you can disable Show notes in Notes and Todo lists for that one folder after reviewing the migration."
        ]

        if !summary.missingMediaDetails.isEmpty {
            lines.append("")
            lines.append("## Missing Media References")
            lines.append(contentsOf: summary.missingMediaDetails.sorted(by: { $0.key < $1.key }).map { "- `\($0.key)`: \($0.value)" })
            lines.append("")
            lines.append("## Missing Media RCA")
            lines.append("")
            lines.append("- Bare filenames such as `boats.jpg` mean Ulysses XML referenced a relative image path, but no matching file was present in that sheet package, its `Media` folder, or the backup-wide media index.")
            lines.append("- `file:///var/mobile/...` references point outside the Ulysses backup, usually to transient iOS app storage such as Messages attachments. These cannot be recovered from the backup unless the original file still exists somewhere else.")
            lines.append("- The affected note title is included before `->` so you can decide whether the note matters or whether it is an old imported/demo sheet.")
        }

        if !summary.unsupportedDetails.isEmpty {
            lines.append("")
            lines.append("## Unsupported XML Detail")
            lines.append(contentsOf: summary.unsupportedDetails.sorted(by: { $0.key < $1.key }).map { "- `\($0.key)`: \($0.value)" })
        }

        lines.append("")
        lines.append("## Input")
        lines.append("")
        lines.append("- Source type: Ulysses backup")
        lines.append("- Groups discovered: \(snapshot.groups.count)")
        lines.append("- Compatibility: \(snapshot.compatibility.verified ? "verified" : "developer override")")
        lines.append("- Verified reader: \(snapshot.compatibility.formatName)")
        lines.append("- Fingerprint schema: \(snapshot.fingerprint.schemaVersion)")
        lines.append("- Sheet packages/readable XML: \(snapshot.fingerprint.sheetPackages)/\(snapshot.fingerprint.readableContentFiles)")
        lines.append("- Store format versions: \(snapshot.fingerprint.storeFormatVersions.keys.sorted().joined(separator: ", "))")
        lines.append("- Top-level XML nodes: \(snapshot.fingerprint.topLevelElements.keys.sorted().joined(separator: ", "))")
        lines.append("- Attachment types: \(snapshot.fingerprint.attachmentTypes.keys.sorted().joined(separator: ", "))")
        lines.append("- Markup identifiers/versions: \(snapshot.fingerprint.markupIdentifiers.keys.sorted().joined(separator: ", ")) / \(snapshot.fingerprint.markupVersions.keys.sorted().joined(separator: ", "))")
        if !snapshot.fingerprint.malformedPlistPaths.isEmpty {
            lines.append("- Unreadable metadata paths: \(snapshot.fingerprint.malformedPlistPaths.sorted().joined(separator: ", "))")
        }
        if !commandLine.isEmpty {
            lines.append("- Command: `\(redactedCommand(commandLine))`")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    func supportJSON(summary: ExportSummary, snapshot: UlyssesLibrarySnapshot, commandLine: [String]) throws -> String {
        let report = SupportReport(
            reportVersion: 2,
            exporterVersion: ExportUlyssesVersion.current,
            command: commandLine.isEmpty ? nil : anonymousCommand(commandLine),
            counts: AnonymousExportCounts(summary),
            missingMediaCategories: anonymousMissingMedia(summary.missingMediaDetails),
            unsupportedNodeNames: summary.unsupportedDetails,
            groupsDiscovered: snapshot.groups.count,
            metadataKeys: metadataKeyCounts(for: snapshot.groups),
            fingerprint: AnonymousFingerprint(snapshot.fingerprint),
            compatibility: snapshot.compatibility,
            notes: [
                "This report excludes note contents, titles, filenames, URLs, and filesystem paths.",
                "The private migration report inside the export contains actionable missing-media details."
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    private func metadataKeyCounts(for groups: [GroupSource]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for group in groups {
            for key in group.metadata.rawKeys {
                counts[key, default: 0] += 1
            }
        }
        return counts
    }

    private func redactedCommand(_ arguments: [String]) -> String {
        arguments.map { shellEscaped(redactHome($0)) }.joined(separator: " ")
    }

    private func anonymousCommand(_ arguments: [String]) -> String {
        var result: [String] = []
        for (index, argument) in arguments.enumerated() {
            if index == 0 {
                result.append(URL(fileURLWithPath: argument).lastPathComponent)
            } else if ["doctor", "migrate"].contains(argument) || argument.hasPrefix("-") {
                result.append(argument)
            }
        }
        return result.joined(separator: " ")
    }

    private func anonymousMissingMedia(_ details: [String: Int]) -> [String: Int] {
        details.reduce(into: [:]) { result, pair in
            let reference = pair.key.components(separatedBy: " -> ").last ?? pair.key
            let category: String
            if reference.localizedCaseInsensitiveContains("file://") {
                category = "external-file-url"
            } else if reference.hasPrefix("image-url:") {
                category = "relative-image-reference"
            } else if reference.hasPrefix("file-attachment:") {
                category = "file-attachment-id"
            } else {
                category = "other-unresolved-reference"
            }
            result[category, default: 0] += pair.value
        }
    }

    private func redactHome(_ value: String) -> String {
        let home = NSHomeDirectory()
        if value == home {
            return "$HOME"
        }
        if value.hasPrefix(home + "/") {
            return "$HOME/" + String(value.dropFirst(home.count + 1))
        }
        return value
    }

    private func shellEscaped(_ value: String) -> String {
        if value.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'"))) == nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

struct SupportReport: Codable, Equatable {
    let reportVersion: Int
    let exporterVersion: String
    let command: String?
    let counts: AnonymousExportCounts
    let missingMediaCategories: [String: Int]
    let unsupportedNodeNames: [String: Int]
    let groupsDiscovered: Int
    let metadataKeys: [String: Int]
    let fingerprint: AnonymousFingerprint
    let compatibility: FormatCompatibility
    let notes: [String]
}

struct AnonymousExportCounts: Codable, Equatable {
    let sheets: Int
    let sidebarNotes: Int
    let fileAttachments: Int
    let inlineImages: Int
    let keywords: Int
    let materialSheets: Int
    let gluedSheets: Int
    let archiveSheets: Int
    let templateSheets: Int
    let trashSheets: Int
    let favoriteSheets: Int
    let savedFilters: Int
    let orderNotes: Int
    let metadataNotes: Int
    let duplicateTitles: Int
    let missingMedia: Int
    let recoveredMedia: Int
    let unsupportedNodes: Int

    init(_ summary: ExportSummary) {
        sheets = summary.sheets
        sidebarNotes = summary.sidebarNotes
        fileAttachments = summary.fileAttachments
        inlineImages = summary.inlineImages
        keywords = summary.keywords
        materialSheets = summary.materialSheets
        gluedSheets = summary.gluedSheets
        archiveSheets = summary.archiveSheets
        templateSheets = summary.templateSheets
        trashSheets = summary.trashSheets
        favoriteSheets = summary.favoriteSheets
        savedFilters = summary.savedFilters
        orderNotes = summary.orderNotes
        metadataNotes = summary.metadataNotes
        duplicateTitles = summary.duplicateTitles
        missingMedia = summary.missingMedia
        recoveredMedia = summary.recoveredMedia
        unsupportedNodes = summary.unsupportedNodes
    }
}

struct AnonymousFingerprint: Codable, Equatable {
    let schemaVersion: Int
    let sheetPackages: Int
    let readableContentFiles: Int
    let malformedContentFiles: Int
    let plistFiles: Int
    let readablePlistFiles: Int
    let malformedPlistFiles: Int
    let malformedPlistKinds: [String: Int]
    let rootElements: [String: Int]
    let topLevelElements: [String: Int]
    let attachmentTypes: [String: Int]
    let markupIdentifiers: [String: Int]
    let markupVersions: [String: Int]
    let markupDefinitions: [String: Int]
    let elementKinds: [String: Int]
    let paragraphKinds: [String: Int]
    let attributeIdentifiers: [String: Int]
    let storeFormatVersions: [String: Int]
    let plistRootTypes: [String: Int]
    let packageExtensions: [String: Int]
    let contentFileNames: [String: Int]
    let storagePackageExtensions: [String: Int]

    init(_ fingerprint: BackupFingerprint) {
        schemaVersion = fingerprint.schemaVersion
        sheetPackages = fingerprint.sheetPackages
        readableContentFiles = fingerprint.readableContentFiles
        malformedContentFiles = fingerprint.malformedContentFiles
        plistFiles = fingerprint.plistFiles
        readablePlistFiles = fingerprint.readablePlistFiles
        malformedPlistFiles = fingerprint.malformedPlistFiles
        malformedPlistKinds = fingerprint.malformedPlistKinds
        rootElements = fingerprint.rootElements
        topLevelElements = fingerprint.topLevelElements
        attachmentTypes = fingerprint.attachmentTypes
        markupIdentifiers = fingerprint.markupIdentifiers
        markupVersions = fingerprint.markupVersions
        markupDefinitions = fingerprint.markupDefinitions
        elementKinds = fingerprint.elementKinds
        paragraphKinds = fingerprint.paragraphKinds
        attributeIdentifiers = fingerprint.attributeIdentifiers
        storeFormatVersions = fingerprint.storeFormatVersions
        plistRootTypes = fingerprint.plistRootTypes
        packageExtensions = fingerprint.packageExtensions
        contentFileNames = fingerprint.contentFileNames
        storagePackageExtensions = fingerprint.storagePackageExtensions
    }
}
