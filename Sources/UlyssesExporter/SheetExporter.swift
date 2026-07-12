import Foundation

struct SheetExporter {
    let mediaIndex: MediaIndex
    let sheetOrderIndex: SheetOrderIndex
    let favoriteSheetPaths: Set<String>
    let groupPathResolver: MigrationLayout

    func export(_ item: PreparedSheetSource, named outputName: String, to outputRoot: URL) throws -> SheetExportResult {
        let source = item.source
        let prepared = item.prepared
        var summary = summary(for: item)
        var destinationDirectory = outputRoot
        let outputGroupPath = groupPathResolver.outputPath(for: source)
        for group in outputGroupPath {
            destinationDirectory.appendPathComponent(sanitizedFileName(group))
        }
        let bundleURL = try TextBundleWriter().writeBundle(
            named: outputName,
            markdown: prepared.rendered.markdown,
            media: prepared.rendered.media,
            in: destinationDirectory,
            dates: prepared.dates
        )
        if outputName != prepared.bundleName { summary.duplicateTitles = 1 }

        return SheetExportResult(
            summary: summary,
            orderEntry: orderEntry(for: item, destinationName: bundleURL.lastPathComponent)
        )
    }

    func analyze(_ item: PreparedSheetSource, named outputName: String) -> SheetExportResult {
        let prepared = item.prepared
        var summary = summary(for: item)
        if outputName != prepared.bundleName { summary.duplicateTitles = 1 }
        return SheetExportResult(
            summary: summary,
            orderEntry: orderEntry(for: item, destinationName: outputName + ".textbundle")
        )
    }

    func prepare(_ source: SheetSource) throws -> PreparedSheetSource {
        let data = try readDataWithRetry(from: source.contentURL)
        var sheet = try UlyssesSheetParser(contentURL: source.contentURL).parse(data)
        let roles = migrationRoles(for: source)
        let isGlued = sheetOrderIndex.clusterInfo(for: source)?.isGlued == true
        let favorite = isFavorite(source, sheet: sheet)
        sheet.migrationTags.append(contentsOf: migrationTags(
            for: source,
            sheet: sheet,
            roles: roles,
            isGlued: isGlued,
            isFavorite: favorite
        ))
        let rendered = MarkdownRenderer(
            mediaResolver: MediaResolver(packageURL: source.packageURL, mediaIndex: mediaIndex)
        ).render(sheet)
        let name = rendered.title.isEmpty ? source.packageURL.deletingPathExtension().lastPathComponent : rendered.title
        return PreparedSheetSource(
            source: source,
            prepared: PreparedSheetExport(
                sheet: sheet,
                rendered: rendered,
                bundleName: sanitizedFileName(name),
                dates: sheetDates(for: source),
                roles: roles,
                isGlued: isGlued,
                isFavorite: favorite
            )
        )
    }

    private func summary(for item: PreparedSheetSource) -> ExportSummary {
        let prepared = item.prepared
        var summary = prepared.rendered.summary
        summary.sheets = 1
        summary.sidebarNotes = prepared.sheet.sidebarNotes.count
        summary.fileAttachments = prepared.sheet.fileAttachmentIDs.count
        summary.keywords = prepared.sheet.keywords.count
        summary.materialSheets = prepared.sheet.isMaterial ? 1 : 0
        summary.gluedSheets = prepared.isGlued ? 1 : 0
        summary.archiveSheets = prepared.roles.contains(.archive) ? 1 : 0
        summary.templateSheets = prepared.roles.contains(.template) ? 1 : 0
        summary.trashSheets = prepared.roles.contains(.trash) ? 1 : 0
        summary.favoriteSheets = prepared.isFavorite ? 1 : 0
        summary.annotateMissingMedia(sourceTitle: prepared.noteTitle)
        return summary
    }

    private func orderEntry(for item: PreparedSheetSource, destinationName: String) -> SheetOrderEntry {
        SheetOrderEntry(
            sourcePackageURL: item.source.packageURL,
            sourcePackageName: item.source.packageURL.lastPathComponent,
            sourceGroupURL: item.source.groupURL,
            sourceGroupPath: item.source.groupPath,
            groupPath: groupPathResolver.outputPath(for: item.source),
            title: item.prepared.noteTitle,
            destinationName: destinationName,
            favorite: item.prepared.isFavorite,
            dates: item.prepared.dates
        )
    }

    private func readDataWithRetry(from url: URL) throws -> Data {
        var lastError: Error?
        for attempt in 0..<5 {
            do {
                return try Data(contentsOf: url)
            } catch {
                lastError = error
                if attempt < 4 {
                    Thread.sleep(forTimeInterval: 0.05 * Double(attempt + 1))
                }
            }
        }
        throw ExportError.contentOpenFailed(url.path, lastError?.localizedDescription ?? "unknown error")
    }

    private func sheetDates(for source: SheetSource) -> SheetDates {
        let packageValues = try? source.packageURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let contentValues = try? source.contentURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let created = packageValues?.creationDate ?? contentValues?.creationDate ?? Date()
        let modified = contentValues?.contentModificationDate
            ?? packageValues?.contentModificationDate
            ?? contentValues?.creationDate
            ?? created
        return SheetDates(created: created, modified: modified)
    }

    private func migrationTags(for source: SheetSource, sheet: UlyssesSheet, roles: Set<UlyssesRole>, isGlued: Bool, isFavorite: Bool) -> [String] {
        var tags: [String] = []
        if sheet.isMaterial {
            tags.append("ulysses/material")
        }
        if isGlued {
            tags.append("ulysses/glued")
        }
        if isFavorite {
            tags.append("ulysses/favorite")
        }
        for role in roles.sorted(by: { $0.rawValue < $1.rawValue }) {
            tags.append("ulysses/\(role.rawValue)")
        }
        return tags
    }

    private func migrationRoles(for source: SheetSource) -> Set<UlyssesRole> {
        var roles = Set<UlyssesRole>()
        let sourceComponents = source.packageURL.pathComponents.map { $0.lowercased() }
        if sourceComponents.contains("trash-ultrash") { roles.insert(.trash) }
        if sourceComponents.contains("templates-ulgroup") { roles.insert(.template) }
        if isUlyssesArchive(url: source.packageURL, groupPath: source.groupPath) {
            roles.insert(.archive)
        }
        return roles
    }

    private func isFavorite(_ source: SheetSource, sheet: UlyssesSheet) -> Bool {
        sheet.isFavorite || favoriteSheetPaths.contains(source.packageURL.standardizedFileURL.path)
    }
}

func isUlyssesArchive(url: URL, groupPath: [String]) -> Bool {
    guard groupPath.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "archive",
          let store = url.pathComponents.first(where: { $0.hasSuffix(".ulstoragebackup") })
    else { return false }
    return store.localizedCaseInsensitiveCompare("Ubiquitous Library.ulstoragebackup") != .orderedSame
}

func isUlyssesInbox(url: URL, groupPath: [String]) -> Bool {
    guard groupPath == ["Inbox"],
          url.lastPathComponent == "Unfiled-ulgroup",
          let store = url.pathComponents.first(where: { $0.hasSuffix(".ulstoragebackup") })
    else { return false }
    return store.localizedCaseInsensitiveCompare("Ubiquitous Library.ulstoragebackup") == .orderedSame
}

func isUlyssesTrash(url: URL) -> Bool {
    url.pathComponents.contains("Trash-ultrash")
}

struct SheetExportResult: Sendable, Equatable {
    let summary: ExportSummary
    let orderEntry: SheetOrderEntry
}
