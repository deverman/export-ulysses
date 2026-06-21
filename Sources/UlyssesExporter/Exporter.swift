import Foundation

public struct ExportSummary: Sendable, Equatable, Codable {
    public var sheets = 0
    public var sidebarNotes = 0
    public var fileAttachments = 0
    public var inlineImages = 0
    public var keywords = 0
    public var materialSheets = 0
    public var gluedSheets = 0
    public var archiveSheets = 0
    public var templateSheets = 0
    public var trashSheets = 0
    public var favoriteSheets = 0
    public var orderNotes = 0
    public var metadataNotes = 0
    public var reportNotes = 0
    public var duplicateTitles = 0
    public var missingMedia = 0
    public var recoveredMedia = 0
    public var unsupportedNodes = 0
    public var unsupportedDetails: [String: Int] = [:]
    public var missingMediaDetails: [String: Int] = [:]

    public mutating func add(_ other: ExportSummary) {
        sheets += other.sheets
        sidebarNotes += other.sidebarNotes
        fileAttachments += other.fileAttachments
        inlineImages += other.inlineImages
        keywords += other.keywords
        materialSheets += other.materialSheets
        gluedSheets += other.gluedSheets
        archiveSheets += other.archiveSheets
        templateSheets += other.templateSheets
        trashSheets += other.trashSheets
        favoriteSheets += other.favoriteSheets
        orderNotes += other.orderNotes
        metadataNotes += other.metadataNotes
        reportNotes += other.reportNotes
        duplicateTitles += other.duplicateTitles
        missingMedia += other.missingMedia
        recoveredMedia += other.recoveredMedia
        unsupportedNodes += other.unsupportedNodes
        for (key, value) in other.unsupportedDetails {
            unsupportedDetails[key, default: 0] += value
        }
        for (key, value) in other.missingMediaDetails {
            missingMediaDetails[key, default: 0] += value
        }
    }

    public mutating func recordUnsupported(_ key: String) {
        unsupportedNodes += 1
        unsupportedDetails[key, default: 0] += 1
    }

    public mutating func recordMissingMedia(_ key: String) {
        missingMedia += 1
        missingMediaDetails[key, default: 0] += 1
    }

    public mutating func annotateMissingMedia(sourceTitle: String) {
        guard !missingMediaDetails.isEmpty else { return }
        let title = sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        missingMediaDetails = missingMediaDetails.reduce(into: [:]) { result, pair in
            result["\(title) -> \(pair.key)", default: 0] += pair.value
        }
    }
}

public struct ExportAnalysis: Sendable, Equatable, Codable {
    public let summary: ExportSummary
    public let reportMarkdown: String
    public let supportJSON: String
}

public struct PreflightResult: Sendable, Equatable {
    public let checks: [PreflightCheck]
    public let analysis: ExportAnalysis?

    public var hasFailures: Bool {
        checks.contains { $0.status == .failure }
    }
}

public struct PreflightCheck: Sendable, Equatable {
    public enum Status: String, Sendable, Equatable {
        case success
        case warning
        case failure
    }

    public let name: String
    public let status: Status
    public let message: String
}

public struct Exporter {
    private let verbose: Bool
    private let maxConcurrentExports: Int

    public init(verbose: Bool = false, maxConcurrentExports: Int = 2) {
        self.verbose = verbose
        self.maxConcurrentExports = max(1, maxConcurrentExports)
    }

    public func run(input: String, output: String, keepGroups: Bool, ignoring ignoredGroups: [String], commandLine: [String] = []) async throws -> ExportSummary {
        let inputURL = URL(fileURLWithPath: input)
        let outputURL = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

        let snapshot = try UlyssesBackupReader().readLibrary(
            in: inputURL,
            keepGroups: keepGroups,
            ignoring: Set(ignoredGroups)
        )
        let sheets = snapshot.sheets

        guard !sheets.isEmpty else {
            throw ExportError.noSheetsFound(inputURL.path)
        }

        if verbose {
            print("Found \(sheets.count) Ulysses sheets.")
        }

        let mediaIndex = MediaIndex(sheets: sheets)
        let sheetOrderIndex = SheetOrderIndex(sheets: sheets)
        return try await export(snapshot, to: outputURL, mediaIndex: mediaIndex, sheetOrderIndex: sheetOrderIndex, commandLine: commandLine)
    }

    public func analyze(input: String, keepGroups: Bool, ignoring ignoredGroups: [String], commandLine: [String] = []) async throws -> ExportAnalysis {
        let inputURL = URL(fileURLWithPath: input)
        let snapshot = try UlyssesBackupReader().readLibrary(
            in: inputURL,
            keepGroups: keepGroups,
            ignoring: Set(ignoredGroups)
        )
        guard !snapshot.sheets.isEmpty else {
            throw ExportError.noSheetsFound(inputURL.path)
        }

        let mediaIndex = MediaIndex(sheets: snapshot.sheets)
        let sheetOrderIndex = SheetOrderIndex(sheets: snapshot.sheets)
        return try await analyze(snapshot, mediaIndex: mediaIndex, sheetOrderIndex: sheetOrderIndex, commandLine: commandLine)
    }

    public func doctor(input: String, output: String?, keepGroups: Bool, ignoring ignoredGroups: [String], commandLine: [String] = []) async -> PreflightResult {
        let inputURL = URL(fileURLWithPath: input)
        var checks: [PreflightCheck] = []

        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            checks.append(PreflightCheck(name: "Input backup", status: .success, message: "Found input directory at \(inputURL.path)."))
        } else {
            let message = inputURL.path.contains("Group Containers")
                ? "Cannot read \(inputURL.path). Confirm the path exists and that the terminal app has Full Disk Access."
                : "Cannot read \(inputURL.path). Pass a Ulysses .ulbackup folder."
            checks.append(PreflightCheck(name: "Input backup", status: .failure, message: message))
            return PreflightResult(checks: checks, analysis: nil)
        }

        if inputURL.pathExtension == "ulbackup" {
            checks.append(PreflightCheck(name: "Backup type", status: .success, message: "Input has the expected .ulbackup extension."))
        } else {
            checks.append(PreflightCheck(name: "Backup type", status: .warning, message: "Input is readable, but it does not end in .ulbackup."))
        }

        if let output {
            checks.append(outputCheck(for: URL(fileURLWithPath: output)))
        } else {
            checks.append(PreflightCheck(name: "Output folder", status: .warning, message: "No output folder was provided; doctor can only validate the input and dry-run analysis."))
        }

        do {
            let analysis = try await analyze(input: input, keepGroups: keepGroups, ignoring: ignoredGroups, commandLine: commandLine)
            checks.append(PreflightCheck(name: "Sheet discovery", status: .success, message: "Found \(analysis.summary.sheets) sheets."))
            if analysis.summary.missingMedia > 0 {
                checks.append(PreflightCheck(name: "Asset links", status: .warning, message: "\(analysis.summary.missingMedia) media references could not be resolved. The export report will list their IDs without note contents."))
            } else {
                checks.append(PreflightCheck(name: "Asset links", status: .success, message: "No missing media references found during analysis."))
            }
            if analysis.summary.unsupportedNodes > 0 {
                checks.append(PreflightCheck(name: "Ulysses markup", status: .warning, message: "\(analysis.summary.unsupportedNodes) unsupported XML nodes were found. The report will list node names."))
            } else {
                checks.append(PreflightCheck(name: "Ulysses markup", status: .success, message: "No unsupported XML nodes found during analysis."))
            }
            return PreflightResult(checks: checks, analysis: analysis)
        } catch {
            checks.append(PreflightCheck(name: "Analysis", status: .failure, message: error.localizedDescription))
            return PreflightResult(checks: checks, analysis: nil)
        }
    }

    private func export(_ snapshot: UlyssesLibrarySnapshot, to outputURL: URL, mediaIndex: MediaIndex, sheetOrderIndex: SheetOrderIndex, commandLine: [String]) async throws -> ExportSummary {
        let sheets = snapshot.sheets
        return try await withThrowingTaskGroup(of: SheetExportResult.self) { group in
            var nextSheetIndex = 0

            func enqueueNextSheet() {
                guard nextSheetIndex < sheets.count else { return }
                let sheet = sheets[nextSheetIndex]
                nextSheetIndex += 1
                group.addTask {
                    try SheetExporter(mediaIndex: mediaIndex, sheetOrderIndex: sheetOrderIndex).export(sheet, to: outputURL)
                }
            }

            for _ in 0..<min(maxConcurrentExports, sheets.count) {
                enqueueNextSheet()
            }

            var summary = ExportSummary()
            var orderEntries: [SheetOrderEntry] = []
            var exported = 0
            for try await result in group {
                exported += 1
                summary.add(result.summary)
                orderEntries.append(result.orderEntry)
                enqueueNextSheet()
                if verbose, exported % 100 == 0 {
                    print("Exported \(exported) sheets.")
                }
            }
            summary.orderNotes = try SheetOrderNoteWriter(
                sheetOrderIndex: sheetOrderIndex,
                outputURL: outputURL
            ).writeOrderNotes(for: orderEntries)
            summary.metadataNotes = try GroupMetadataNoteWriter(outputURL: outputURL)
                .writeMetadataNotes(for: snapshot.groups)
            summary.reportNotes = 1
            try ExportReportWriter(outputURL: outputURL).writeReport(
                summary: summary,
                snapshot: snapshot,
                commandLine: commandLine
            )
            return summary
        }
    }

    private func analyze(_ snapshot: UlyssesLibrarySnapshot, mediaIndex: MediaIndex, sheetOrderIndex: SheetOrderIndex, commandLine: [String]) async throws -> ExportAnalysis {
        let sheets = snapshot.sheets
        return try await withThrowingTaskGroup(of: SheetExportResult.self) { group in
            for sheet in sheets {
                group.addTask {
                    try SheetExporter(mediaIndex: mediaIndex, sheetOrderIndex: sheetOrderIndex).analyze(sheet)
                }
            }

            var summary = ExportSummary()
            var orderEntries: [SheetOrderEntry] = []
            for try await result in group {
                summary.add(result.summary)
                orderEntries.append(result.orderEntry)
            }
            summary.orderNotes = SheetOrderNoteWriter(sheetOrderIndex: sheetOrderIndex, outputURL: URL(fileURLWithPath: "/"))
                .countOrderNotes(for: orderEntries)
            summary.metadataNotes = GroupMetadataNoteWriter(outputURL: URL(fileURLWithPath: "/"))
                .countMetadataNotes(for: snapshot.groups)
            summary.reportNotes = 1
            summary.duplicateTitles = estimatedDuplicateTitles(for: orderEntries)

            let writer = ExportReportWriter(outputURL: URL(fileURLWithPath: "/"))
            let markdown = writer.reportMarkdown(summary: summary, snapshot: snapshot, commandLine: commandLine)
            let supportJSON = try writer.supportJSON(summary: summary, snapshot: snapshot, commandLine: commandLine)
            return ExportAnalysis(summary: summary, reportMarkdown: markdown, supportJSON: supportJSON)
        }
    }

    private func estimatedDuplicateTitles(for entries: [SheetOrderEntry]) -> Int {
        var counts: [String: Int] = [:]
        for entry in entries {
            let path = (entry.groupPath + [entry.destinationName]).joined(separator: "/").lowercased()
            counts[path, default: 0] += 1
        }
        return counts.values.reduce(0) { total, count in total + max(0, count - 1) }
    }

    private func outputCheck(for outputURL: URL) -> PreflightCheck {
        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: outputURL.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                return PreflightCheck(name: "Output folder", status: .failure, message: "\(outputURL.path) exists and is not a directory.")
            }
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: outputURL.path)) ?? []
            let status: PreflightCheck.Status = contents.isEmpty ? .success : .warning
            let message = contents.isEmpty
                ? "Output directory exists and is empty."
                : "Output directory exists and is not empty; duplicate note names will receive numeric suffixes."
            return PreflightCheck(name: "Output folder", status: status, message: message)
        }

        let parent = outputURL.deletingLastPathComponent()
        if FileManager.default.isWritableFile(atPath: parent.path) {
            return PreflightCheck(name: "Output folder", status: .success, message: "Output directory can be created under \(parent.path).")
        }
        return PreflightCheck(name: "Output folder", status: .failure, message: "Cannot write to \(parent.path). Choose a writable destination.")
    }
}

public enum ExportError: Error, LocalizedError {
    case noSheetsFound(String)
    case invalidXML(String)
    case contentOpenFailed(String, String)

    public var errorDescription: String? {
        switch self {
        case .noSheetsFound(let path):
            "No Ulysses .ulysses/Content.xml sheets were found under \(path). Use a Ulysses .ulbackup folder such as ~/Library/Group Containers/X5AZV975AG.com.soulmen.shared/Ulysses/Backups/Latest Backup.ulbackup."
        case .invalidXML(let path):
            "Could not parse Ulysses Content.xml at \(path)."
        case .contentOpenFailed(let path, let reason):
            "Could not open Ulysses Content.xml at \(path): \(reason)"
        }
    }
}

public struct SheetSource: Sendable, Equatable {
    public let packageURL: URL
    public let contentURL: URL
    public let groupURL: URL
    public let groupPath: [String]
}

public struct UlyssesLibrarySnapshot: Sendable, Equatable {
    public let rootURL: URL
    public let sheets: [SheetSource]
    public let groups: [GroupSource]
}

public struct GroupSource: Sendable, Equatable {
    public let groupURL: URL
    public let infoURL: URL
    public let relativePath: String
    public let groupPath: [String]
    public let metadata: UlyssesGroupMetadata
}

public struct UlyssesGroupMetadata: Sendable, Equatable {
    public let displayName: String?
    public let userIconName: String?
    public let userTintColor: String?
    public let childOrder: [String]
    public let sheetClusters: [[String]]
    public let countingGoal: [String: String]
    public let activitySessionCount: Int
    public let rawKeys: [String]

    public var hasUserVisibleMetadata: Bool {
        userIconName != nil
            || userTintColor != nil
            || !countingGoal.isEmpty
            || activitySessionCount > 0
    }
}

struct UlyssesBackupReader {
    func readLibrary(in inputURL: URL, keepGroups: Bool, ignoring ignoredGroups: Set<String>) throws -> UlyssesLibrarySnapshot {
        let root = inputURL.standardizedFileURL
        let sheets = try findSheets(in: root, keepGroups: keepGroups, ignoring: ignoredGroups)
        let groups = findGroups(in: root, keepGroups: keepGroups, ignoring: ignoredGroups)
        return UlyssesLibrarySnapshot(rootURL: root, sheets: sheets, groups: groups)
    }

    func findSheets(in inputURL: URL, keepGroups: Bool, ignoring ignoredGroups: Set<String>) throws -> [SheetSource] {
        let root = inputURL.standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var sheets: [SheetSource] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "ulysses" else { continue }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }
            let contentURL = url.appendingPathComponent("Content.xml")
            guard FileManager.default.isReadableFile(atPath: contentURL.path) else { continue }

            let groupPath = keepGroups ? groupPath(forDirectoryAt: url.deletingLastPathComponent(), root: root, ignoring: ignoredGroups) : []
            if groupPath.contains(where: ignoredGroups.contains) {
                enumerator.skipDescendants()
                continue
            }

            sheets.append(SheetSource(packageURL: url, contentURL: contentURL, groupURL: url.deletingLastPathComponent(), groupPath: groupPath))
            enumerator.skipDescendants()
        }
        return sheets
    }

    private func findGroups(in inputURL: URL, keepGroups: Bool, ignoring ignoredGroups: Set<String>) -> [GroupSource] {
        guard keepGroups,
              let enumerator = FileManager.default.enumerator(
                at: inputURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              )
        else {
            return []
        }

        var groups: [GroupSource] = []
        var seen = Set<String>()

        for case let url as URL in enumerator {
            guard url.lastPathComponent == "Info.ulgroup" else { continue }
            let groupURL = url.deletingLastPathComponent()
            let groupPath = groupPath(forDirectoryAt: groupURL, root: inputURL, ignoring: ignoredGroups)
            guard !groupPath.isEmpty, !groupPath.contains(where: ignoredGroups.contains) else { continue }
            let standardizedPath = groupURL.standardizedFileURL.path
            guard !seen.contains(standardizedPath), let metadata = metadata(forGroupInfoAt: url) else { continue }
            seen.insert(standardizedPath)
            let relativePath = relativePath(for: groupURL, root: inputURL)
            groups.append(GroupSource(
                groupURL: groupURL,
                infoURL: url,
                relativePath: relativePath,
                groupPath: groupPath,
                metadata: metadata
            ))
        }

        return groups.sorted { $0.groupPath.lexicographicallyPrecedes($1.groupPath) }
    }

    private func groupPath(forDirectoryAt directoryURL: URL, root: URL, ignoring ignoredGroups: Set<String>) -> [String] {
        let rootPath = root.standardizedFileURL.path
        let parentPath = directoryURL.standardizedFileURL.path
        let relativePath: String
        if parentPath == rootPath {
            relativePath = ""
        } else if parentPath.hasPrefix(rootPath + "/") {
            relativePath = String(parentPath.dropFirst(rootPath.count + 1))
        } else {
            relativePath = directoryURL.lastPathComponent
        }
        let relativeComponents = relativePath.split(separator: "/").map(String.init)

        var groups: [String] = []
        var current = root
        for component in relativeComponents {
            current.appendPathComponent(component)
            if component.hasSuffix(".ulstoragebackup") {
                if component != "Ubiquitous Library.ulstoragebackup",
                   let displayName = displayName(forGroupAt: current.appendingPathComponent("Content")) {
                    groups.append(displayName)
                }
                continue
            }
            if component == "Content" || component == "Groups-ulgroup" {
                continue
            }
            if component == "Unfiled-ulgroup" {
                groups.append("Inbox")
                continue
            }
            if component == "Trash-ultrash" {
                groups.append("Trash")
                continue
            }
            guard component.hasSuffix("-ulgroup") else { continue }
            groups.append(displayName(forGroupAt: current) ?? component.replacingOccurrences(of: "-ulgroup", with: ""))
        }
        return groups.filter { !ignoredGroups.contains($0) }
    }

    private func relativePath(for url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private func displayName(forGroupAt url: URL) -> String? {
        let infoURL = url.appendingPathComponent("Info.ulgroup")
        return metadata(forGroupInfoAt: infoURL)?.displayName
    }

    private func metadata(forGroupInfoAt infoURL: URL) -> UlyssesGroupMetadata? {
        guard let data = try? Data(contentsOf: infoURL),
              let dictionary = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return nil
        }

        let countingGoal = (dictionary["countingGoal"] as? [String: Any])?.reduce(into: [String: String]()) { result, pair in
            result[pair.key] = String(describing: pair.value)
        } ?? [:]
        let activitySessionCount = (dictionary["activityTracking"] as? [[String: Any]])?.count ?? 0

        return UlyssesGroupMetadata(
            displayName: dictionary["DisplayName"] as? String
                ?? dictionary["displayName"] as? String
                ?? dictionary["name"] as? String,
            userIconName: dictionary["userIconName"] as? String,
            userTintColor: dictionary["userTintColor"] as? String,
            childOrder: dictionary["childOrder"] as? [String] ?? [],
            sheetClusters: dictionary["sheetClusters"] as? [[String]] ?? [],
            countingGoal: countingGoal,
            activitySessionCount: activitySessionCount,
            rawKeys: dictionary.keys.sorted()
        )
    }
}

struct SheetExporter {
    let mediaIndex: MediaIndex
    let sheetOrderIndex: SheetOrderIndex

    func export(_ source: SheetSource, to outputRoot: URL) throws -> SheetExportResult {
        let prepared = try prepare(source)
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
        summary.favoriteSheets = prepared.sheet.isFavorite ? 1 : 0
        summary.annotateMissingMedia(sourceTitle: prepared.noteTitle)

        var destinationDirectory = outputRoot
        for group in source.groupPath {
            destinationDirectory.appendPathComponent(sanitizedFileName(group))
        }
        let writeResult = try TextBundleWriter().writeBundle(
            named: prepared.bundleName,
            markdown: prepared.rendered.markdown,
            media: prepared.rendered.media,
            in: destinationDirectory,
            dates: prepared.dates
        )
        if writeResult.usedDuplicateName {
            summary.duplicateTitles += 1
        }

        return SheetExportResult(
            summary: summary,
            orderEntry: SheetOrderEntry(
                sourcePackageName: source.packageURL.lastPathComponent,
                sourceGroupURL: source.groupURL,
                groupPath: source.groupPath,
                title: prepared.noteTitle,
                destinationName: writeResult.bundleURL.lastPathComponent,
                dates: prepared.dates
            )
        )
    }

    func analyze(_ source: SheetSource) throws -> SheetExportResult {
        let prepared = try prepare(source)
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
        summary.favoriteSheets = prepared.sheet.isFavorite ? 1 : 0
        summary.annotateMissingMedia(sourceTitle: prepared.noteTitle)

        return SheetExportResult(
            summary: summary,
            orderEntry: SheetOrderEntry(
                sourcePackageName: source.packageURL.lastPathComponent,
                sourceGroupURL: source.groupURL,
                groupPath: source.groupPath,
                title: prepared.noteTitle,
                destinationName: prepared.bundleName + ".textbundle",
                dates: prepared.dates
            )
        )
    }

    private func prepare(_ source: SheetSource) throws -> PreparedSheetExport {
        let data = try readDataWithRetry(from: source.contentURL)
        var sheet = try UlyssesSheetParser(contentURL: source.contentURL).parse(data)
        let roles = migrationRoles(for: source)
        let isGlued = sheetOrderIndex.clusterInfo(for: source)?.isGlued == true
        sheet.migrationTags.append(contentsOf: migrationTags(for: source, sheet: sheet, roles: roles, isGlued: isGlued))
        let renderer = MarkdownRenderer(mediaResolver: MediaResolver(packageURL: source.packageURL, mediaIndex: mediaIndex))
        let rendered = renderer.render(sheet)

        let bundleName = sanitizedFileName(rendered.title.isEmpty ? source.packageURL.deletingPathExtension().lastPathComponent : rendered.title)
        let dates = sheetDates(for: source)
        return PreparedSheetExport(
            sheet: sheet,
            rendered: rendered,
            bundleName: bundleName,
            dates: dates,
            roles: roles,
            isGlued: isGlued
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

    private func migrationTags(for source: SheetSource, sheet: UlyssesSheet, roles: Set<UlyssesRole>, isGlued: Bool) -> [String] {
        var tags: [String] = []
        if sheet.isMaterial {
            tags.append("ulysses/material")
        }
        if isGlued {
            tags.append("ulysses/glued")
        }
        if sheet.isFavorite {
            tags.append("ulysses/favorite")
        }
        for role in roles.sorted(by: { $0.rawValue < $1.rawValue }) {
            tags.append("ulysses/\(role.rawValue)")
        }
        return tags
    }

    private func migrationRoles(for source: SheetSource) -> Set<UlyssesRole> {
        Set(source.groupPath.compactMap(UlyssesRole.init(groupName:)))
    }
}

struct SheetExportResult: Sendable, Equatable {
    let summary: ExportSummary
    let orderEntry: SheetOrderEntry
}

struct PreparedSheetExport: Equatable {
    let sheet: UlyssesSheet
    let rendered: RenderedSheet
    let bundleName: String
    let dates: SheetDates
    let roles: Set<UlyssesRole>
    let isGlued: Bool

    var noteTitle: String {
        rendered.title.isEmpty ? bundleName : rendered.title
    }
}

enum UlyssesRole: String, Sendable, Comparable {
    case archive
    case template
    case trash

    init?(groupName: String) {
        let normalized = groupName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "archive":
            self = .archive
        case "template", "templates":
            self = .template
        case "trash":
            self = .trash
        default:
            return nil
        }
    }

    static func < (lhs: UlyssesRole, rhs: UlyssesRole) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct SheetOrderEntry: Sendable, Equatable {
    let sourcePackageName: String
    let sourceGroupURL: URL
    let groupPath: [String]
    let title: String
    let destinationName: String
    let dates: SheetDates
}

struct SheetDates: Sendable, Equatable {
    let created: Date
    let modified: Date
}

struct SheetClusterInfo: Sendable, Equatable {
    let order: Int
    let clusterSize: Int

    var isGlued: Bool { clusterSize > 1 }
}

struct GroupSheetOrder: Sendable, Equatable {
    let groupURL: URL
    let sheetClusters: [[String]]
}

struct SheetOrderIndex: Sendable, Equatable {
    private let ordersByGroupPath: [String: GroupSheetOrder]
    private let clusterInfoBySheetPath: [String: SheetClusterInfo]

    init(sheets: [SheetSource]) {
        let uniqueGroupURLs = Dictionary(grouping: sheets, by: { $0.groupURL.standardizedFileURL.path })
            .compactMap { $0.value.first?.groupURL }

        var ordersByGroupPath: [String: GroupSheetOrder] = [:]
        var clusterInfoBySheetPath: [String: SheetClusterInfo] = [:]

        for groupURL in uniqueGroupURLs {
            let clusters = Self.sheetClusters(for: groupURL)
            guard !clusters.isEmpty else { continue }

            let order = GroupSheetOrder(groupURL: groupURL, sheetClusters: clusters)
            ordersByGroupPath[groupURL.standardizedFileURL.path] = order

            for (clusterIndex, cluster) in clusters.enumerated() {
                for sheetName in cluster {
                    let sheetURL = groupURL.appendingPathComponent(sheetName)
                    clusterInfoBySheetPath[sheetURL.standardizedFileURL.path] = SheetClusterInfo(
                        order: clusterIndex,
                        clusterSize: cluster.count
                    )
                }
            }
        }

        self.ordersByGroupPath = ordersByGroupPath
        self.clusterInfoBySheetPath = clusterInfoBySheetPath
    }

    func order(for groupURL: URL) -> GroupSheetOrder? {
        ordersByGroupPath[groupURL.standardizedFileURL.path]
    }

    func clusterInfo(for source: SheetSource) -> SheetClusterInfo? {
        clusterInfoBySheetPath[source.packageURL.standardizedFileURL.path]
    }

    private static func sheetClusters(for groupURL: URL) -> [[String]] {
        let infoURL = groupURL.appendingPathComponent("Info.ulgroup")
        guard let data = try? Data(contentsOf: infoURL),
              let dictionary = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let rawClusters = dictionary["sheetClusters"] as? [[String]]
        else {
            return []
        }

        return rawClusters
            .map { cluster in cluster.filter { $0.hasSuffix(".ulysses") } }
            .filter { !$0.isEmpty }
    }
}

struct SheetOrderNoteWriter {
    let sheetOrderIndex: SheetOrderIndex
    let outputURL: URL

    func writeOrderNotes(for entries: [SheetOrderEntry]) throws -> Int {
        try orderNotePlans(for: entries).reduce(0) { written, plan in
            _ = try TextBundleWriter().writeBundle(
                named: plan.title,
                markdown: plan.markdown,
                in: plan.destinationDirectory,
                dates: plan.dates
            )
            return written + 1
        }
    }

    func countOrderNotes(for entries: [SheetOrderEntry]) -> Int {
        orderNotePlans(for: entries).count
    }

    private func orderNotePlans(for entries: [SheetOrderEntry]) -> [OrderNotePlan] {
        let entriesByGroup = Dictionary(grouping: entries, by: { $0.sourceGroupURL.standardizedFileURL.path })
        var plans: [OrderNotePlan] = []

        for groupEntries in entriesByGroup.values {
            guard let first = groupEntries.first,
                  !first.groupPath.isEmpty,
                  let groupOrder = sheetOrderIndex.order(for: first.sourceGroupURL)
            else {
                continue
            }

            let orderedClusters = orderedEntries(from: groupEntries, groupOrder: groupOrder)
            let hasGluedCluster = orderedClusters.contains { $0.count > 1 }
            let orderedSheetCount = orderedClusters.flatMap { $0 }.count
            guard orderedSheetCount > 1 || hasGluedCluster else { continue }

            var destinationDirectory = outputURL
            for group in first.groupPath {
                destinationDirectory.appendPathComponent(sanitizedFileName(group))
            }

            let dates = datesForOrderNote(entries: groupEntries)
            plans.append(OrderNotePlan(
                destinationDirectory: destinationDirectory,
                title: orderNoteTitle(for: first.groupPath),
                markdown: markdown(for: orderedClusters, groupPath: first.groupPath, hasGluedCluster: hasGluedCluster),
                dates: dates
            ))
        }

        return plans
    }

    private func orderedEntries(from entries: [SheetOrderEntry], groupOrder: GroupSheetOrder) -> [[SheetOrderEntry]] {
        let entriesBySourceName = Dictionary(uniqueKeysWithValues: entries.map { ($0.sourcePackageName, $0) })
        var orderedClusters: [[SheetOrderEntry]] = []
        var included = Set<String>()

        for cluster in groupOrder.sheetClusters {
            let resolved = cluster.compactMap { sheetName -> SheetOrderEntry? in
                guard let entry = entriesBySourceName[sheetName] else { return nil }
                included.insert(sheetName)
                return entry
            }
            if !resolved.isEmpty {
                orderedClusters.append(resolved)
            }
        }

        let remaining = entries
            .filter { !included.contains($0.sourcePackageName) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        orderedClusters.append(contentsOf: remaining.map { [$0] })

        return orderedClusters
    }

    private func markdown(for clusters: [[SheetOrderEntry]], groupPath: [String], hasGluedCluster: Bool) -> String {
        var lines = [
            "# \(orderNoteTitle(for: groupPath))",
            "",
            hasGluedCluster ? "#ulysses/order-index #ulysses/glued" : "#ulysses/order-index",
            "",
            "Folder: \(groupPath.joined(separator: " / "))",
            "",
            "## Sheets"
        ]

        for (index, cluster) in clusters.enumerated() {
            if cluster.count == 1, let entry = cluster.first {
                lines.append("\(index + 1). \(link(for: entry))")
                continue
            }

            lines.append("\(index + 1). Glued sheets")
            for entry in cluster {
                lines.append("   - \(link(for: entry))")
            }
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    private func link(for entry: SheetOrderEntry) -> String {
        let wikiTitle = entry.title
            .replacingOccurrences(of: "[[", with: "[")
            .replacingOccurrences(of: "]]", with: "]")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "[[\(wikiTitle)]] (`\(entry.destinationName)`)"
    }

    private func orderNoteTitle(for groupPath: [String]) -> String {
        "Ulysses Sheet Order: \(groupPath.joined(separator: " / "))"
    }

    private func datesForOrderNote(entries: [SheetOrderEntry]) -> SheetDates {
        let created = entries.map(\.dates.created).min() ?? Date()
        let modified = entries.map(\.dates.modified).max() ?? Date()
        return SheetDates(created: created, modified: modified)
    }
}

struct OrderNotePlan: Equatable {
    let destinationDirectory: URL
    let title: String
    let markdown: String
    let dates: SheetDates
}

struct TextBundleWriteResult: Equatable {
    let bundleURL: URL
    let usedDuplicateName: Bool
}

struct TextBundleWriter {
    func writeBundle(
        named name: String,
        markdown: String,
        media: [ReferencedMedia] = [],
        in destinationDirectory: URL,
        dates: SheetDates
    ) throws -> TextBundleWriteResult {
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let requestedURL = destinationDirectory
            .appendingPathComponent(sanitizedFileName(name))
            .appendingPathExtension("textbundle")
        let bundleURL = try DestinationAllocator.shared.createBundle(at: requestedURL)
        let textURL = bundleURL.appendingPathComponent("text.markdown")
        let infoURL = bundleURL.appendingPathComponent("info.json")
        let assetsURL = bundleURL.appendingPathComponent("assets")

        try markdown.write(to: textURL, atomically: true, encoding: .utf8)
        try infoJSON(for: dates).write(to: infoURL, atomically: true, encoding: .utf8)

        for item in media {
            guard let sourceURL = item.sourceURL, FileManager.default.fileExists(atPath: sourceURL.path) else { continue }
            try FileManager.default.copyItem(at: sourceURL, to: assetsURL.appendingPathComponent(item.destinationName))
        }

        try apply(dates: dates, to: [bundleURL, assetsURL, textURL, infoURL])
        return TextBundleWriteResult(
            bundleURL: bundleURL,
            usedDuplicateName: bundleURL.lastPathComponent != requestedURL.lastPathComponent
        )
    }

    private func apply(dates: SheetDates, to urls: [URL]) throws {
        let attributes: [FileAttributeKey: Any] = [
            .creationDate: dates.created,
            .modificationDate: dates.modified
        ]
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
        }
    }

    private func infoJSON(for dates: SheetDates) throws -> String {
        let payload: [String: Any] = [
            "version": 2,
            "type": "net.daringfireball.markdown",
            "transient": false,
            "creatorIdentifier": "org.deverman.export-ulysses",
            "flatExtension": "markdown",
            "created": Int(dates.created.timeIntervalSince1970),
            "modified": Int(dates.modified.timeIntervalSince1970)
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}

struct GroupMetadataNoteWriter {
    let outputURL: URL

    func writeMetadataNotes(for groups: [GroupSource]) throws -> Int {
        try metadataNotePlans(for: groups).reduce(0) { written, plan in
            _ = try TextBundleWriter().writeBundle(
                named: plan.title,
                markdown: plan.markdown,
                in: plan.destinationDirectory,
                dates: plan.dates
            )
            return written + 1
        }
    }

    func countMetadataNotes(for groups: [GroupSource]) -> Int {
        metadataNotePlans(for: groups).count
    }

    private func metadataNotePlans(for groups: [GroupSource]) -> [MetadataNotePlan] {
        groups.compactMap { group in
            let roles = Set(group.groupPath.suffix(1).compactMap(UlyssesRole.init(groupName:)))
            guard group.metadata.hasUserVisibleMetadata || !roles.isEmpty else { return nil }
            var destinationDirectory = outputURL
            for component in group.groupPath {
                destinationDirectory.appendPathComponent(sanitizedFileName(component))
            }
            let dates = groupDates(for: group)
            let title = metadataTitle(for: group)
            return MetadataNotePlan(
                destinationDirectory: destinationDirectory,
                title: title,
                markdown: markdown(for: group, roles: roles),
                dates: dates
            )
        }
    }

    private func markdown(for group: GroupSource, roles: Set<UlyssesRole>) -> String {
        var lines = [
            "# \(metadataTitle(for: group))",
            "",
            metadataTags(for: roles).joined(separator: " "),
            "",
            "## Group",
            "",
            "- Display name: \(group.metadata.displayName ?? group.groupPath.last ?? "Untitled")",
            "- FSNotes folder: \(group.groupPath.joined(separator: " / "))"
        ]

        if let icon = group.metadata.userIconName {
            lines.append("- Ulysses icon: \(icon)")
        }
        if let tint = group.metadata.userTintColor {
            lines.append("- Ulysses color: \(tint)")
        }
        if !roles.isEmpty {
            lines.append("- Ulysses role: \(roles.sorted().map(\.rawValue).joined(separator: ", "))")
        }
        if !group.metadata.countingGoal.isEmpty {
            lines.append("")
            lines.append("## Goal")
            for (key, value) in group.metadata.countingGoal.sorted(by: { $0.key < $1.key }) {
                lines.append("- \(key): \(value)")
            }
        }
        if group.metadata.activitySessionCount > 0 {
            lines.append("")
            lines.append("## Activity")
            lines.append("- Activity sessions recorded by Ulysses: \(group.metadata.activitySessionCount)")
        }
        if !group.metadata.childOrder.isEmpty || !group.metadata.sheetClusters.isEmpty {
            lines.append("")
            lines.append("## Original Order")
            if !group.metadata.childOrder.isEmpty {
                lines.append("- Child order entries: \(group.metadata.childOrder.count)")
            }
            if !group.metadata.sheetClusters.isEmpty {
                lines.append("- Sheet clusters: \(group.metadata.sheetClusters.count)")
                let glued = group.metadata.sheetClusters.filter { $0.count > 1 }.count
                if glued > 0 {
                    lines.append("- Glued clusters: \(glued)")
                }
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private func metadataTitle(for group: GroupSource) -> String {
        "Ulysses Metadata: \(group.groupPath.joined(separator: " / "))"
    }

    private func metadataTags(for roles: Set<UlyssesRole>) -> [String] {
        var tags = ["#ulysses/group-metadata"]
        tags.append(contentsOf: roles.sorted().map { "#ulysses/\($0.rawValue)" })
        return tags
    }

    private func groupDates(for group: GroupSource) -> SheetDates {
        let infoValues = try? group.infoURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let groupValues = try? group.groupURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let created = groupValues?.creationDate ?? infoValues?.creationDate ?? Date()
        let modified = infoValues?.contentModificationDate
            ?? groupValues?.contentModificationDate
            ?? created
        return SheetDates(created: created, modified: modified)
    }
}

struct MetadataNotePlan: Equatable {
    let destinationDirectory: URL
    let title: String
    let markdown: String
    let dates: SheetDates
}

struct ExportReportWriter {
    let outputURL: URL

    func writeReport(summary: ExportSummary, snapshot: UlyssesLibrarySnapshot, commandLine: [String]) throws {
        let dates = SheetDates(created: Date(), modified: Date())
        _ = try TextBundleWriter().writeBundle(
            named: "Ulysses Export Report",
            markdown: reportMarkdown(summary: summary, snapshot: snapshot, commandLine: commandLine),
            in: outputURL,
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
            "- Sidebar notes: \(summary.sidebarNotes)",
            "- Sidebar file attachments: \(summary.fileAttachments)",
            "- Inline images: \(summary.inlineImages)",
            "- Keywords: \(summary.keywords)",
            "- Material sheets: \(summary.materialSheets)",
            "- Glued sheets: \(summary.gluedSheets)",
            "- Archive sheets: \(summary.archiveSheets)",
            "- Template sheets: \(summary.templateSheets)",
            "- Trash sheets: \(summary.trashSheets)",
            "- Favorite sheets: \(summary.favoriteSheets)",
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
            "- Ulysses sidebar notes, comments, annotations, keywords, material status, glued sheet status, archive/template/trash role, and group metadata as visible Markdown",
            "- TextBundle `info.json` dates for FSNotes",
            "",
            "## What FSNotes Cannot Model Directly",
            "",
            "- Ulysses inspector/sidebar UI placement",
            "- Ulysses group icons, colors, goals, and activity tracking as native FSNotes folder settings",
            "- Ulysses favorites as native FSNotes pins",
            "",
            "## Support File",
            "",
            "A privacy-safe JSON support report was written to `.export-ulysses/ulysses-export-report.json`. FSNotes should not show that hidden folder in the note list."
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
        if !commandLine.isEmpty {
            lines.append("- Command: `\(redactedCommand(commandLine))`")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    func supportJSON(summary: ExportSummary, snapshot: UlyssesLibrarySnapshot, commandLine: [String]) throws -> String {
        let report = SupportReport(
            version: 1,
            command: commandLine.isEmpty ? nil : redactedCommand(commandLine),
            counts: summary,
            groupsDiscovered: snapshot.groups.count,
            metadataKeys: metadataKeyCounts(for: snapshot.groups),
            notes: [
                "This report intentionally excludes note contents.",
                "Missing media keys and unsupported XML node names are included for support diagnostics."
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
    let version: Int
    let command: String?
    let counts: ExportSummary
    let groupsDiscovered: Int
    let metadataKeys: [String: Int]
    let notes: [String]
}

final class DestinationAllocator: @unchecked Sendable {
    static let shared = DestinationAllocator()
    private let lock = NSLock()

    func createBundle(at requestedURL: URL) throws -> URL {
        lock.lock()
        defer { lock.unlock() }

        let bundleURL = availableDestination(for: requestedURL)
        try FileManager.default.createDirectory(at: bundleURL.appendingPathComponent("assets"), withIntermediateDirectories: true)
        return bundleURL
    }
}

struct UlyssesSheet: Equatable {
    var body: [XMLNode] = []
    var sidebarNotes: [[XMLNode]] = []
    var fileAttachmentIDs: [String] = []
    var keywords: [String] = []
    var settings: [String: String] = [:]
    var migrationTags: [String] = []
    var unsupportedAttachmentTypes: [String] = []

    var isMaterial: Bool {
        settings["material"]?.localizedCaseInsensitiveCompare("YES") == .orderedSame
    }

    var isFavorite: Bool {
        settings.contains { key, value in
            key.localizedCaseInsensitiveContains("favorite")
                && ["yes", "true", "1"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
    }
}

enum XMLNode: Equatable {
    case text(String)
    case element(name: String, attributes: [String: String], children: [XMLNode])

    var plainText: String {
        switch self {
        case .text(let value):
            value
        case .element(_, _, let children):
            children.map(\.plainText).joined()
        }
    }

    var elementName: String? {
        if case .element(let name, _, _) = self { name } else { nil }
    }
}

final class UlyssesSheetParser: NSObject, XMLParserDelegate {
    private let contentURL: URL
    private var stack: [(name: String, attributes: [String: String], children: [XMLNode])] = []
    private var parsedSheet = UlyssesSheet()
    private var parserError: Error?

    init(contentURL: URL) {
        self.contentURL = contentURL
    }

    func parse(_ data: Data) throws -> UlyssesSheet {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse(), parserError == nil else {
            throw parserError ?? ExportError.invalidXML(contentURL.path)
        }
        return parsedSheet
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        parserError = parseError
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        stack.append((elementName, attributeDict, []))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !stack.isEmpty else { return }
        stack[stack.count - 1].children.append(.text(string))
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard let completed = stack.popLast() else { return }
        let node = XMLNode.element(name: completed.name, attributes: completed.attributes, children: completed.children)

        if let parent = stack.last?.name, parent == "sheet" {
            collectTopLevel(node)
        } else if stack.isEmpty {
            // Finished the root node.
        } else {
            stack[stack.count - 1].children.append(node)
        }
    }

    private func collectTopLevel(_ node: XMLNode) {
        guard case .element(let name, let attributes, let children) = node else { return }
        if name == "string" {
            parsedSheet.body = children
        } else if name == "setting" {
            if let settingName = attributes["name"], let value = attributes["value"] {
                parsedSheet.settings[settingName] = value
            }
        } else if name == "attachment" {
            switch attributes["type"] {
            case "note":
                if let stringNode = children.first(where: { $0.elementName == "string" }),
                   case .element(_, _, let noteChildren) = stringNode {
                    parsedSheet.sidebarNotes.append(noteChildren)
                }
            case "file":
                let id = children.map(\.plainText).joined().trimmingCharacters(in: .whitespacesAndNewlines)
                if !id.isEmpty {
                    parsedSheet.fileAttachmentIDs.append(id)
                }
            case "keywords":
                let keywords = children.map(\.plainText).joined()
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                parsedSheet.keywords.append(contentsOf: keywords)
            case let type?:
                parsedSheet.unsupportedAttachmentTypes.append(type)
            case nil:
                parsedSheet.unsupportedAttachmentTypes.append("unknown")
            }
        }
    }
}

struct RenderedSheet: Equatable {
    var title: String
    var markdown: String
    var media: [ReferencedMedia]
    var summary: ExportSummary
}

struct ReferencedMedia: Equatable {
    var sourceURL: URL?
    var destinationName: String
    var recoveredFromGlobalIndex = false
}

struct MarkdownRenderer {
    let mediaResolver: MediaResolver

    func render(_ sheet: UlyssesSheet) -> RenderedSheet {
        var context = RenderContext(mediaResolver: mediaResolver)
        var sections: [String] = []
        let body = renderBlockNodes(sheet.body, context: &context)
        sections.append(body)

        if !sheet.fileAttachmentIDs.isEmpty {
            sections.append(renderFileAttachments(sheet.fileAttachmentIDs, context: &context))
        }

        if !sheet.sidebarNotes.isEmpty {
            let notes = sheet.sidebarNotes.enumerated().map { index, nodes in
                "### Note \(index + 1)\n\n\(renderBlockNodes(nodes, context: &context))"
            }.joined(separator: "\n\n")
            sections.append("## Ulysses Sidebar Notes\n\n\(notes)")
        }

        if !sheet.keywords.isEmpty {
            sections.append("## Ulysses Keywords\n\n" + sheet.keywords.map { "#\(tagSlug($0))" }.joined(separator: " "))
        }

        if !sheet.migrationTags.isEmpty {
            sections.append("## Ulysses Migration Tags\n\n" + sheet.migrationTags.map { "#\(tagSlug($0))" }.joined(separator: " "))
        }

        if !sheet.unsupportedAttachmentTypes.isEmpty {
            for type in sheet.unsupportedAttachmentTypes {
                context.summary.recordUnsupported("attachment:\(type)")
            }
            sections.append("## Ulysses Migration Notes\n\nUnsupported attachment types: \(sheet.unsupportedAttachmentTypes.joined(separator: ", "))")
        }

        let markdown = sections
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
            + "\n"

        return RenderedSheet(
            title: title(from: body),
            markdown: markdown,
            media: context.media,
            summary: context.summary
        )
    }

    private func renderFileAttachments(_ ids: [String], context: inout RenderContext) -> String {
        let lines = ids.map { id -> String in
            if let media = context.resolveMedia(id: id) {
                let path = assetMarkdownPath(for: media.destinationName)
                if isImageFile(media.destinationName) {
                    return "- ![\(media.destinationName)](\(path))"
                }
                return "- [\(media.destinationName)](\(path))"
            }
            context.summary.recordMissingMedia("file:\(id)")
            return "- Missing Ulysses file attachment: `\(id)`"
        }
        return "## Ulysses Attachments\n\n" + lines.joined(separator: "\n")
    }

    private func renderBlockNodes(_ nodes: [XMLNode], context: inout RenderContext) -> String {
        nodes.compactMap { node -> String? in
            guard case .element(let name, _, let children) = node else {
                let text = node.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            }

            switch name {
            case "p":
                return renderParagraph(children, context: &context)
            default:
                context.summary.recordUnsupported("block:\(name)")
                let text = renderInline(node, context: &context).trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            }
        }
        .joined(separator: "\n\n")
    }

    private func renderParagraph(_ children: [XMLNode], context: inout RenderContext) -> String? {
        if let table = renderTableIfPresent(in: children, context: &context) {
            return table
        }

        let (prefix, inlineNodes) = paragraphPrefix(children)
        let content = inlineNodes.map { renderInline($0, context: &context) }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if prefix.isEmpty, content.isEmpty {
            return nil
        }

        return prefix + content
    }

    private func renderTableIfPresent(in children: [XMLNode], context: inout RenderContext) -> String? {
        guard children.contains(where: { node in
            guard case .element("tags", _, let tagNodes) = node else { return false }
            return tagNodes.contains {
                if case .element("tag", let attributes, _) = $0 {
                    return attributes["kind"] == "table"
                }
                return false
            }
        }) else {
            return nil
        }

        guard let tableAttribute = children.first(where: { node in
            if case .element("attribute", let attributes, _) = node {
                return attributes["identifier"] == "table"
            }
            return false
        }), case .element(_, _, let attributeChildren) = tableAttribute,
           let tableNode = attributeChildren.first(where: { $0.elementName == "table" }) else {
            return nil
        }

        let rows = tableRows(from: tableNode, context: &context)
        guard !rows.isEmpty else { return nil }
        let columnCount = rows.map(\.count).max() ?? 1
        let normalizedRows = rows.map { row in
            row + Array(repeating: "", count: max(0, columnCount - row.count))
        }
        let header = normalizedRows[0].map(escapeTableCell).joined(separator: " | ")
        let separator = Array(repeating: "---", count: columnCount).joined(separator: " | ")
        let body = normalizedRows.dropFirst()
            .map { "| " + $0.map(escapeTableCell).joined(separator: " | ") + " |" }
            .joined(separator: "\n")

        if body.isEmpty {
            return """
            | \(header) |
            | \(separator) |
            """
        }

        return """
        | \(header) |
        | \(separator) |
        \(body)
        """
    }

    private func tableRows(from tableNode: XMLNode, context: inout RenderContext) -> [[String]] {
        guard case .element("table", _, let tableChildren) = tableNode else { return [] }
        return tableChildren.compactMap { rowNode -> [String]? in
            guard case .element("row", _, let rowChildren) = rowNode else { return nil }
            return rowChildren.compactMap { cellNode -> String? in
                guard case .element("cell", _, let cellChildren) = cellNode else { return nil }
                return cellChildren.map { renderInline($0, context: &context) }
                    .joined(separator: " ")
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    private func escapeTableCell(_ cell: String) -> String {
        cell.replacingOccurrences(of: "|", with: "\\|")
    }

    private func paragraphPrefix(_ children: [XMLNode]) -> (String, [XMLNode]) {
        guard let first = children.first,
              case .element("tags", _, let tagNodes) = first else {
            return ("", children)
        }

        var prefix = ""
        for tagNode in tagNodes {
            guard case .element("tag", let attributes, let tagChildren) = tagNode else { continue }
            let text = tagChildren.map(\.plainText).joined()
            switch attributes["kind"] {
            case "heading1", "heading2", "heading3", "heading4", "heading5", "heading6":
                prefix += text.isEmpty ? "# " : text
            case "unorderedList", "orderedList":
                prefix += text.isEmpty ? "- " : text
            default:
                prefix += text
            }
        }

        return (prefix, Array(children.dropFirst()))
    }

    private func renderInline(_ node: XMLNode, context: inout RenderContext) -> String {
        switch node {
        case .text(let text):
            return text
        case .element(let name, let attributes, let children):
            switch name {
            case "element":
                return renderUlyssesElement(kind: attributes["kind"], children: children, context: &context)
            case "attribute", "tags", "tag", "table", "row", "cell", "column", "size", "p", "bookmark":
                return children.map { renderInline($0, context: &context) }.joined()
            case "string":
                return children.map { renderInline($0, context: &context) }.joined()
            case "escape":
                return children.map(\.plainText).joined()
            default:
                context.summary.recordUnsupported("node:\(name)")
                return children.map { renderInline($0, context: &context) }.joined()
            }
        }
    }

    private func renderUlyssesElement(kind: String?, children: [XMLNode], context: inout RenderContext) -> String {
        switch kind {
        case "strong":
            return "**\(elementBody(children, context: &context))**"
        case "emphasis", "emph":
            return "*\(elementBody(children, context: &context))*"
        case "mark":
            return "==\(elementBody(children, context: &context))=="
        case "delete":
            return "~~\(elementBody(children, context: &context))~~"
        case "inlineNative":
            return elementBody(children, context: &context)
        case "annotation":
            let body = elementBody(children, context: &context)
            let annotation = attributeValue("text", in: children)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if annotation.isEmpty {
                return body
            }
            return "\(body) <!-- Ulysses annotation: \(annotation) -->"
        case "code":
            return "`\(elementBody(children, context: &context))`"
        case "inlineComment", "comment":
            return "<!-- \(elementBody(children, context: &context).trimmingCharacters(in: .whitespacesAndNewlines)) -->"
        case "link":
            let title = attributeValue("title", in: children)
            let url = attributeValue("URL", in: children)
            let body = elementBody(children, context: &context).trimmingCharacters(in: .whitespacesAndNewlines)
            if let url, !url.isEmpty {
                return "[\(body.isEmpty ? (title ?? url) : body)](\(url))"
            }
            if let title, !title.isEmpty, !body.isEmpty {
                return "[\(body)](\(title))"
            }
            return body
        case "image":
            context.summary.inlineImages += 1
            let description = attributeValue("description", in: children) ?? ""
            if let id = attributeValue("image", in: children), let media = context.resolveMedia(id: id) {
                return "![\(description)](\(assetMarkdownPath(for: media.destinationName)))"
            }
            if let url = attributeValue("URL", in: children), !url.isEmpty {
                if url.hasPrefix("http://") || url.hasPrefix("https://") {
                    return "![\(description)](\(url))"
                }
                if let media = context.resolveMedia(pathOrURL: url) {
                    return "![\(description)](\(assetMarkdownPath(for: media.destinationName)))"
                }
                context.summary.recordMissingMedia("image-url:\(url)")
                return "![\(description)](\(url))"
            }
            if let id = attributeValue("image", in: children), !id.isEmpty {
                context.summary.recordMissingMedia("image:\(id)")
            } else {
                context.summary.recordMissingMedia("image:unknown")
            }
            return "![\(description)]()"
        case "footnote":
            return "[^\(elementBody(children, context: &context))]"
        case "video":
            if let url = attributeValue("URL", in: children), !url.isEmpty {
                return "[Video](\(url))"
            }
            return elementBody(children, context: &context)
        default:
            context.summary.recordUnsupported("element:\(kind ?? "unknown")")
            return elementBody(children, context: &context)
        }
    }

    private func elementBody(_ children: [XMLNode], context: inout RenderContext) -> String {
        children.filter {
            if case .element("attribute", _, _) = $0 {
                return false
            }
            return true
        }.map { renderInline($0, context: &context) }.joined()
    }

    private func attributeValue(_ identifier: String, in children: [XMLNode]) -> String? {
        for child in children {
            guard case .element("attribute", let attributes, let attributeChildren) = child,
                  attributes["identifier"] == identifier else { continue }
            if let nested = attributeChildren.first,
               case .element("size", let sizeAttributes, _) = nested,
               identifier == "size" {
                return sizeAttributes.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            }
            return attributeChildren.map(\.plainText).joined()
        }
        return nil
    }

    private func title(from markdown: String) -> String {
        for line in markdown.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("#") {
                return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }
}

struct RenderContext {
    let mediaResolver: MediaResolver
    var media: [ReferencedMedia] = []
    var mediaByDestination: Set<String> = []
    var summary = ExportSummary()

    mutating func resolveMedia(id: String) -> ReferencedMedia? {
        guard let source = mediaResolver.mediaFile(matching: id) else { return nil }
        return recordMedia(source)
    }

    mutating func resolveMedia(pathOrURL: String) -> ReferencedMedia? {
        guard let source = mediaResolver.mediaFile(pathOrURL: pathOrURL) else { return nil }
        return recordMedia(source)
    }

    private mutating func recordMedia(_ source: ResolvedMedia) -> ReferencedMedia {
        if source.recoveredFromGlobalIndex {
            summary.recoveredMedia += 1
        }
        let sourceURL = source.url
        let baseName = sourceURL.lastPathComponent
        var destinationName = baseName
        var counter = 1
        while mediaByDestination.contains(destinationName) {
            let ext = (baseName as NSString).pathExtension
            let stem = (baseName as NSString).deletingPathExtension
            destinationName = ext.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(ext)"
            counter += 1
        }
        mediaByDestination.insert(destinationName)
        let mediaReference = ReferencedMedia(
            sourceURL: sourceURL,
            destinationName: destinationName,
            recoveredFromGlobalIndex: source.recoveredFromGlobalIndex
        )
        media.append(mediaReference)
        return mediaReference
    }
}

struct ResolvedMedia: Equatable {
    let url: URL
    let recoveredFromGlobalIndex: Bool
}

struct MediaResolver: Equatable {
    let packageURL: URL
    let mediaIndex: MediaIndex
    private var mediaURL: URL { packageURL.appendingPathComponent("Media") }

    func mediaFile(matching id: String) -> ResolvedMedia? {
        if let local = localMediaFile(matching: id) {
            return ResolvedMedia(url: local, recoveredFromGlobalIndex: false)
        }
        guard let fallback = mediaIndex.mediaFile(matching: id) else { return nil }
        return ResolvedMedia(url: fallback, recoveredFromGlobalIndex: true)
    }

    func mediaFile(pathOrURL: String) -> ResolvedMedia? {
        let decoded = pathOrURL.removingPercentEncoding ?? pathOrURL
        if decoded.hasPrefix("file://"), let url = URL(string: decoded), FileManager.default.fileExists(atPath: url.path) {
            return ResolvedMedia(url: url, recoveredFromGlobalIndex: false)
        }
        let local = mediaURL.appendingPathComponent(decoded)
        if FileManager.default.fileExists(atPath: local.path) {
            return ResolvedMedia(url: local, recoveredFromGlobalIndex: false)
        }
        let packageLocal = packageURL.appendingPathComponent(decoded)
        if FileManager.default.fileExists(atPath: packageLocal.path) {
            return ResolvedMedia(url: packageLocal, recoveredFromGlobalIndex: false)
        }
        return nil
    }

    private func localMediaFile(matching id: String) -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: mediaURL, includingPropertiesForKeys: nil) else {
            return nil
        }
        return files.first { $0.lastPathComponent.contains(".\(id).") || $0.deletingPathExtension().lastPathComponent.hasSuffix(".\(id)") }
    }
}

struct MediaIndex: Sendable, Equatable {
    let filesByID: [String: [URL]]

    init(sheets: [SheetSource]) {
        var filesByID: [String: [URL]] = [:]
        for sheet in sheets {
            let mediaURL = sheet.packageURL.appendingPathComponent("Media")
            guard let files = try? FileManager.default.contentsOfDirectory(at: mediaURL, includingPropertiesForKeys: nil) else {
                continue
            }
            for file in files {
                guard let id = Self.mediaID(from: file.lastPathComponent) else { continue }
                filesByID[id, default: []].append(file)
            }
        }
        self.filesByID = filesByID.mapValues { files in
            files.sorted { $0.path < $1.path }
        }
    }

    func mediaFile(matching id: String) -> URL? {
        filesByID[id]?.first
    }

    private static func mediaID(from fileName: String) -> String? {
        let stem = (fileName as NSString).deletingPathExtension
        guard let candidate = stem.split(separator: ".").last.map(String.init), !candidate.isEmpty else {
            return nil
        }
        return candidate
    }
}

private func sanitizedFileName(_ name: String) -> String {
    let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
    let sanitized = name.components(separatedBy: invalid).joined(separator: "-")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return sanitized.isEmpty ? "Untitled" : String(sanitized.prefix(180))
}

private func tagSlug(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_/"))
    return value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        .reduce(into: "") { $0.append($1) }
        .replacingOccurrences(of: "--", with: "-")
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

private func assetMarkdownPath(for destinationName: String) -> String {
    "assets/\(markdownPath(for: destinationName))"
}

private func markdownPath(for fileName: String) -> String {
    let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "#%?[]"))
    return fileName.addingPercentEncoding(withAllowedCharacters: allowed) ?? fileName
}

private func isImageFile(_ fileName: String) -> Bool {
    switch (fileName as NSString).pathExtension.lowercased() {
    case "apng", "avif", "bmp", "gif", "heic", "heif", "jpeg", "jpg", "png", "svg", "tif", "tiff", "webp":
        return true
    default:
        return false
    }
}

private func availableDestination(for destination: URL) -> URL {
    var availableDestination = destination
    let baseName = destination.deletingPathExtension().lastPathComponent
    let pathExtension = destination.pathExtension
    var version = 0
    while FileManager.default.fileExists(atPath: availableDestination.path) {
        version += 1
        var nextDestination = destination
            .deletingLastPathComponent()
            .appendingPathComponent("\(baseName) (\(version))")
        if !pathExtension.isEmpty {
            nextDestination.appendPathExtension(pathExtension)
        }
        availableDestination = nextDestination
    }
    return availableDestination
}
