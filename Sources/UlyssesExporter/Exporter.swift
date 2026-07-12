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
    public var savedFilters = 0
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
        savedFilters += other.savedFilters
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
        try requireEmptyOutput(outputURL)
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
        let groupPathResolver = GroupPathResolver(sheets: sheets, groups: snapshot.groups)
        return try await export(snapshot, to: outputURL, mediaIndex: mediaIndex, sheetOrderIndex: sheetOrderIndex, groupPathResolver: groupPathResolver, commandLine: commandLine)
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
        let groupPathResolver = GroupPathResolver(sheets: snapshot.sheets, groups: snapshot.groups)
        return try await analyze(snapshot, mediaIndex: mediaIndex, sheetOrderIndex: sheetOrderIndex, groupPathResolver: groupPathResolver, commandLine: commandLine)
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
            if analysis.summary.trashSheets > 0 {
                checks.append(PreflightCheck(
                    name: "FSNotes Trash",
                    status: .warning,
                    message: "\(analysis.summary.trashSheets) Ulysses Trash sheets will be written to <output>/Trash. Select the output as FSNotes' Default Storage and verify its Trash location before using Empty Trash."
                ))
            }
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

    private func export(_ snapshot: UlyssesLibrarySnapshot, to outputURL: URL, mediaIndex: MediaIndex, sheetOrderIndex: SheetOrderIndex, groupPathResolver: GroupPathResolver, commandLine: [String]) async throws -> ExportSummary {
        let sheetExporter = SheetExporter(
            mediaIndex: mediaIndex,
            sheetOrderIndex: sheetOrderIndex,
            favoriteSheetPaths: snapshot.favoriteSheetPaths,
            groupPathResolver: groupPathResolver
        )
        let prepared = try await process(snapshot.sheets) { try sheetExporter.prepare($0) }
        let names = OutputNameResolver(prepared: prepared, groupPaths: groupPathResolver)
        let results = try await process(prepared) { item in
            try sheetExporter.export(item, named: names.name(for: item.source), to: outputURL)
        }
        var (summary, orderEntries) = aggregate(results)
        if verbose { print("Exported \(results.count) sheets.") }
        let indexCounts = try MigrationIndexWriter(
            sheetOrderIndex: sheetOrderIndex,
            groupPathResolver: groupPathResolver,
            outputURL: outputURL
        ).write(entries: orderEntries, groups: snapshot.groups)
        summary.orderNotes = indexCounts.orderNotes
        summary.metadataNotes = indexCounts.metadataNotes
        summary.savedFilters = snapshot.filters.filter { !$0.isInTrash }.count
        summary.reportNotes = 1
        try LibraryCompanionWriter(outputURL: outputURL, groupPathResolver: groupPathResolver).write(
            snapshot: snapshot,
            entries: orderEntries,
            summary: summary
        )
        try ExportReportWriter(outputURL: outputURL).writeReport(
            summary: summary,
            snapshot: snapshot,
            commandLine: commandLine
        )
        return summary
    }

    private func analyze(_ snapshot: UlyssesLibrarySnapshot, mediaIndex: MediaIndex, sheetOrderIndex: SheetOrderIndex, groupPathResolver: GroupPathResolver, commandLine: [String]) async throws -> ExportAnalysis {
        let sheetExporter = SheetExporter(
            mediaIndex: mediaIndex,
            sheetOrderIndex: sheetOrderIndex,
            favoriteSheetPaths: snapshot.favoriteSheetPaths,
            groupPathResolver: groupPathResolver
        )
        let prepared = try await process(snapshot.sheets) { try sheetExporter.prepare($0) }
        let names = OutputNameResolver(prepared: prepared, groupPaths: groupPathResolver)
        let results = prepared.map { sheetExporter.analyze($0, named: names.name(for: $0.source)) }
        var (summary, orderEntries) = aggregate(results)
        let indexCounts = MigrationIndexWriter(
            sheetOrderIndex: sheetOrderIndex,
            groupPathResolver: groupPathResolver,
            outputURL: URL(fileURLWithPath: "/")
        )
            .counts(entries: orderEntries, groups: snapshot.groups)
        summary.orderNotes = indexCounts.orderNotes
        summary.metadataNotes = indexCounts.metadataNotes
        summary.savedFilters = snapshot.filters.filter { !$0.isInTrash }.count
        summary.reportNotes = 1

        let writer = ExportReportWriter(outputURL: URL(fileURLWithPath: "/"))
        return try ExportAnalysis(
            summary: summary,
            reportMarkdown: writer.reportMarkdown(summary: summary, snapshot: snapshot, commandLine: commandLine),
            supportJSON: writer.supportJSON(summary: summary, snapshot: snapshot, commandLine: commandLine)
        )
    }

    private func process<Input: Sendable, Result: Sendable>(
        _ inputs: [Input],
        operation: @escaping @Sendable (Input) throws -> Result
    ) async throws -> [Result] {
        try await withThrowingTaskGroup(of: Result.self) { group in
            var iterator = inputs.makeIterator()
            for _ in 0..<min(maxConcurrentExports, inputs.count) {
                if let input = iterator.next() { group.addTask { try operation(input) } }
            }

            var results: [Result] = []
            results.reserveCapacity(inputs.count)
            for try await result in group {
                results.append(result)
                if let input = iterator.next() { group.addTask { try operation(input) } }
            }
            return results
        }
    }

    private func aggregate(_ results: [SheetExportResult]) -> (ExportSummary, [SheetOrderEntry]) {
        var summary = ExportSummary()
        for result in results { summary.add(result.summary) }
        return (summary, results.map(\.orderEntry))
    }

    private func outputCheck(for outputURL: URL) -> PreflightCheck {
        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: outputURL.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                return PreflightCheck(name: "Output folder", status: .failure, message: "\(outputURL.path) exists and is not a directory.")
            }
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: outputURL.path)) ?? []
            let meaningfulContents = contents.filter { $0 != ".DS_Store" }
            let status: PreflightCheck.Status = meaningfulContents.isEmpty ? .success : .failure
            let message = meaningfulContents.isEmpty
                ? "Output directory exists and is empty."
                : "Output directory is not empty. Choose a new empty folder so an earlier migration is never duplicated or overwritten."
            return PreflightCheck(name: "Output folder", status: status, message: message)
        }

        var parent = outputURL.deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: parent.path), parent.path != "/" {
            parent.deleteLastPathComponent()
        }
        if FileManager.default.isWritableFile(atPath: parent.path) {
            return PreflightCheck(name: "Output folder", status: .success, message: "Output directory can be created from writable parent \(parent.path).")
        }
        return PreflightCheck(name: "Output folder", status: .failure, message: "Cannot write to \(parent.path). Choose a writable destination.")
    }

    private func requireEmptyOutput(_ outputURL: URL) throws {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: outputURL.path, isDirectory: &isDirectory) else { return }
        guard isDirectory.boolValue else { throw ExportError.outputNotDirectory(outputURL.path) }
        let contents = try FileManager.default.contentsOfDirectory(atPath: outputURL.path)
            .filter { $0 != ".DS_Store" }
        guard contents.isEmpty else { throw ExportError.outputNotEmpty(outputURL.path) }
    }
}

public enum ExportError: Error, LocalizedError {
    case noSheetsFound(String)
    case invalidXML(String)
    case contentOpenFailed(String, String)
    case outputNotDirectory(String)
    case outputNotEmpty(String)
    case destinationCollision(String)

    public var errorDescription: String? {
        switch self {
        case .noSheetsFound(let path):
            "No Ulysses .ulysses/Content.xml sheets were found under \(path). Use a Ulysses .ulbackup folder such as ~/Library/Group Containers/X5AZV975AG.com.soulmen.shared/Ulysses/Backups/Latest Backup.ulbackup."
        case .invalidXML(let path):
            "Could not parse Ulysses Content.xml at \(path)."
        case .contentOpenFailed(let path, let reason):
            "Could not open Ulysses Content.xml at \(path): \(reason)"
        case .outputNotDirectory(let path):
            "The output path \(path) exists and is not a directory. Choose a new empty output folder."
        case .outputNotEmpty(let path):
            "The output folder \(path) is not empty. Choose a new empty folder, or remove the previous migration after reviewing it."
        case .destinationCollision(let path):
            "Two exported items resolved to \(path). This is an exporter naming error; run with --analyze and include the support report in a bug report."
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
    public let favoriteSheetPaths: Set<String>
    public let filters: [UlyssesFilter]
}

public struct UlyssesFilter: Sendable, Equatable {
    public let name: String
    public let groupPath: [String]
    public let queryDescription: String
    public let isInTrash: Bool
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
        let normalizedIgnoredGroups = Set(ignoredGroups.map(Self.normalizedGroupName))
        let sheets = try findSheets(in: root, keepGroups: keepGroups, ignoring: normalizedIgnoredGroups)
        let groups = findGroups(in: root, keepGroups: keepGroups, ignoring: normalizedIgnoredGroups)
        return UlyssesLibrarySnapshot(
            rootURL: root,
            sheets: sheets,
            groups: groups,
            favoriteSheetPaths: findFavoriteSheetPaths(in: root),
            filters: findFilters(in: root, keepGroups: keepGroups, ignoring: normalizedIgnoredGroups)
        )
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

            let sourceGroupPath = groupPath(forDirectoryAt: url.deletingLastPathComponent(), root: root)
            if sourceGroupPath.contains(where: { ignoredGroups.contains(Self.normalizedGroupName($0)) }) {
                enumerator.skipDescendants()
                continue
            }
            let groupPath = keepGroups ? sourceGroupPath : []

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
            let groupPath = groupPath(forDirectoryAt: groupURL, root: inputURL)
            guard !groupPath.isEmpty,
                  !groupPath.contains(where: { ignoredGroups.contains(Self.normalizedGroupName($0)) })
            else { continue }
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

    private func groupPath(forDirectoryAt directoryURL: URL, root: URL) -> [String] {
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
        return groups
    }

    private func findFavoriteSheetPaths(in root: URL) -> Set<String> {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var favorites = Set<String>()
        for case let url as URL in enumerator where url.lastPathComponent == "favorites" {
            guard url.deletingLastPathComponent().lastPathComponent == "Content",
                  let data = try? Data(contentsOf: url),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let order = plist["order"] as? [String]
            else { continue }

            let contentURL = url.deletingLastPathComponent()
            favorites.formUnion(order.map {
                contentURL.appendingPathComponent($0).standardizedFileURL.path
            })
        }
        return favorites
    }

    private func findFilters(in root: URL, keepGroups: Bool, ignoring ignoredGroups: Set<String>) -> [UlyssesFilter] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var filters: [UlyssesFilter] = []
        for case let url as URL in enumerator where url.lastPathComponent == "Info.ulfilter" {
            let filterURL = url.deletingLastPathComponent()
            let sourcePath = groupPath(forDirectoryAt: filterURL.deletingLastPathComponent(), root: root)
            guard !sourcePath.contains(where: { ignoredGroups.contains(Self.normalizedGroupName($0)) }),
                  let data = try? Data(contentsOf: url),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { continue }

            let name = plist["displayName"] as? String
                ?? filterURL.lastPathComponent.replacingOccurrences(of: "-ulfilter", with: "")
            let query = plist["query"].map(Self.describePlist) ?? "Unavailable"
            filters.append(UlyssesFilter(
                name: name,
                groupPath: keepGroups ? sourcePath : [],
                queryDescription: query,
                isInTrash: filterURL.pathComponents.contains("Trash-ultrash")
            ))
            enumerator.skipDescendants()
        }
        return filters.sorted {
            ($0.groupPath + [$0.name]).lexicographicallyPrecedes($1.groupPath + [$1.name])
        }
    }

    private static func describePlist(_ value: Any) -> String {
        switch value {
        case let dictionary as [String: Any]:
            return dictionary.keys.sorted().map { "\($0): \(describePlist(dictionary[$0]!))" }.joined(separator: "; ")
        case let array as [Any]:
            return array.map(describePlist).joined(separator: ", ")
        default:
            return String(describing: value)
        }
    }

    private static func normalizedGroupName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
    let favoriteSheetPaths: Set<String>
    let groupPathResolver: GroupPathResolver

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

struct GroupPathResolver: Sendable, Equatable {
    private let pathsBySourceGroup: [String: [String]]

    init(sheets: [SheetSource], groups: [GroupSource]) {
        var nodesByIdentity: [String: GroupNode] = [:]
        var identitiesBySourceGroup: [String: [String]] = [:]
        var rootSourceGroups = Set<String>()
        let records = sheets.map { ($0.groupURL, $0.groupPath) }
            + groups.map { ($0.groupURL, $0.groupPath) }

        for (groupURL, groupPath) in records {
            let sourceKey = groupURL.standardizedFileURL.path
            if isUlyssesInbox(url: groupURL, groupPath: groupPath) {
                identitiesBySourceGroup[sourceKey] = []
                rootSourceGroups.insert(sourceKey)
                continue
            }
            var identities = Self.groupIdentities(for: groupURL)
            if identities.count == groupPath.count + 1,
               identities.first.map({ URL(fileURLWithPath: $0).pathExtension == "ulstoragebackup" }) == true {
                identities.removeFirst()
            }
            guard identities.count == groupPath.count else {
                identitiesBySourceGroup[sourceKey] = []
                continue
            }
            identitiesBySourceGroup[sourceKey] = identities
            for (depth, identity) in identities.enumerated() {
                let originalName = sanitizedFileName(groupPath[depth])
                let displayName: String
                if depth == 0 && isUlyssesArchive(url: groupURL, groupPath: groupPath) {
                    displayName = "Archive (Ulysses)"
                } else if originalName.localizedCaseInsensitiveCompare("Trash") == .orderedSame,
                          identity.components(separatedBy: "/").last != "Trash-ultrash" {
                    displayName = "Trash (Ulysses Group)"
                } else if depth == 0 && originalName.localizedCaseInsensitiveCompare("Inbox") == .orderedSame {
                    displayName = "Inbox (Ulysses Group)"
                } else {
                    displayName = originalName
                }
                nodesByIdentity[identity] = GroupNode(
                    identity: identity,
                    parentIdentity: depth == 0 ? nil : identities[depth - 1],
                    displayName: displayName,
                    depth: depth
                )
            }
        }

        var resolvedByIdentity: [String: [String]] = [:]
        let maximumDepth = nodesByIdentity.values.map(\.depth).max() ?? -1
        if maximumDepth >= 0 {
            for depth in 0...maximumDepth {
                let nodes = nodesByIdentity.values.filter { $0.depth == depth }
                let byParent = Dictionary(grouping: nodes) {
                    $0.parentIdentity.flatMap { resolvedByIdentity[$0] }?.joined(separator: "/").lowercased() ?? ""
                }
                for siblings in byParent.values {
                    let byName = Dictionary(grouping: siblings) { $0.displayName.lowercased() }
                    var used = Set(byName.values.compactMap { $0.count == 1 ? $0[0].displayName.lowercased() : nil })
                    for sameName in byName.values.sorted(by: Self.groupOrder) {
                        let stores = sameName.filter { URL(fileURLWithPath: $0.identity).pathExtension == "ulstoragebackup" }
                        let canonical = stores.count == 1 ? stores[0] : nil
                        if let canonical { used.insert(canonical.displayName.lowercased()) }
                        for node in sameName.sorted(by: { $0.identity < $1.identity }) {
                            let component: String
                            if sameName.count == 1 || node == canonical {
                                component = node.displayName
                            } else {
                                component = Self.disambiguatedName(for: node, used: &used)
                            }
                            let parent = node.parentIdentity.flatMap { resolvedByIdentity[$0] } ?? []
                            resolvedByIdentity[node.identity] = parent + [component]
                        }
                    }
                }
            }
        }

        var paths = resolvedByIdentity
        for (identity, path) in resolvedByIdentity where URL(fileURLWithPath: identity).pathExtension == "ulstoragebackup" {
            paths[URL(fileURLWithPath: identity).appendingPathComponent("Content").standardizedFileURL.path] = path
        }
        pathsBySourceGroup = records.reduce(into: paths) { result, record in
            let sourceKey = record.0.standardizedFileURL.path
            if rootSourceGroups.contains(sourceKey) {
                result[sourceKey] = []
                return
            }
            let identities = identitiesBySourceGroup[sourceKey] ?? []
            let resolved = identities.last.flatMap { resolvedByIdentity[$0] }
                ?? record.1.map(sanitizedFileName)
            result[sourceKey] = resolved
        }
    }

    func outputPath(for source: SheetSource) -> [String] {
        if isUlyssesTrash(url: source.packageURL) { return ["Trash"] }
        return pathsBySourceGroup[source.groupURL.standardizedFileURL.path] ?? source.groupPath.map(sanitizedFileName)
    }

    func outputPath(for group: GroupSource) -> [String] {
        if isUlyssesTrash(url: group.groupURL) { return ["Trash"] }
        return pathsBySourceGroup[group.groupURL.standardizedFileURL.path] ?? group.groupPath.map(sanitizedFileName)
    }

    private static func groupIdentities(for groupURL: URL) -> [String] {
        let components = groupURL.standardizedFileURL.pathComponents
        guard let storeIndex = components.firstIndex(where: { $0.hasSuffix(".ulstoragebackup") }) else { return [] }
        var identities: [String] = []
        var current = URL(fileURLWithPath: "/")
        for (index, component) in components.enumerated() {
            if component != "/" { current.appendPathComponent(component) }
            guard index >= storeIndex else { continue }
            if index == storeIndex {
                if component.localizedCaseInsensitiveCompare("Ubiquitous Library.ulstoragebackup") != .orderedSame {
                    identities.append(current.standardizedFileURL.path)
                }
                continue
            }
            if component == "Content" || component == "Groups-ulgroup" { continue }
            if component == "Unfiled-ulgroup" || component == "Trash-ultrash" || component.hasSuffix("-ulgroup") {
                identities.append(current.standardizedFileURL.path)
            }
        }
        return identities
    }

    private static func groupOrder(_ lhs: [GroupNode], _ rhs: [GroupNode]) -> Bool {
        let left = lhs.first?.displayName ?? ""
        let right = rhs.first?.displayName ?? ""
        let comparison = left.localizedStandardCompare(right)
        if comparison != .orderedSame { return comparison == .orderedAscending }
        return (lhs.first?.identity ?? "") < (rhs.first?.identity ?? "")
    }

    private static func disambiguatedName(for node: GroupNode, used: inout Set<String>) -> String {
        let rawIdentifier = URL(fileURLWithPath: node.identity).lastPathComponent
            .replacingOccurrences(of: "-ulgroup", with: "")
            .replacingOccurrences(of: ".ulstoragebackup", with: "")
        var length = min(8, rawIdentifier.count)
        var candidate = "\(node.displayName) [\(rawIdentifier.prefix(length))]"
        while used.contains(candidate.lowercased()), length < rawIdentifier.count {
            length = min(length + 4, rawIdentifier.count)
            candidate = "\(node.displayName) [\(rawIdentifier.prefix(length))]"
        }
        var counter = 1
        let base = candidate
        while used.contains(candidate.lowercased()) {
            candidate = "\(base) (\(counter))"
            counter += 1
        }
        used.insert(candidate.lowercased())
        return candidate
    }
}

private struct GroupNode: Sendable, Equatable {
    let identity: String
    let parentIdentity: String?
    let displayName: String
    let depth: Int
}

struct OutputNameResolver: Sendable, Equatable {
    private let namesBySourcePath: [String: String]

    init(prepared: [PreparedSheetSource], groupPaths: GroupPathResolver) {
        let byFolder = Dictionary(grouping: prepared) {
            groupPaths.outputPath(for: $0.source).map(sanitizedFileName).joined(separator: "/").lowercased()
        }
        var resolved: [String: String] = [:]

        for items in byFolder.values {
            let byRequestedName = Dictionary(grouping: items) { $0.prepared.bundleName.lowercased() }
            var used = Set<String>()
            var duplicates: [PreparedSheetSource] = []

            for group in byRequestedName.values {
                let sorted = group.sorted { $0.source.packageURL.path < $1.source.packageURL.path }
                guard let primary = sorted.first else { continue }
                resolved[primary.source.packageURL.standardizedFileURL.path] = primary.prepared.bundleName
                used.insert(primary.prepared.bundleName.lowercased())
                duplicates.append(contentsOf: sorted.dropFirst())
            }

            for item in duplicates.sorted(by: Self.allocationOrder) {
                let base = item.prepared.bundleName
                var counter = 1
                var candidate = "\(base) (\(counter))"
                while used.contains(candidate.lowercased()) {
                    counter += 1
                    candidate = "\(base) (\(counter))"
                }
                resolved[item.source.packageURL.standardizedFileURL.path] = candidate
                used.insert(candidate.lowercased())
            }
        }
        namesBySourcePath = resolved
    }

    func name(for source: SheetSource) -> String {
        namesBySourcePath[source.packageURL.standardizedFileURL.path]
            ?? sanitizedFileName(source.packageURL.deletingPathExtension().lastPathComponent)
    }

    private static func allocationOrder(_ lhs: PreparedSheetSource, _ rhs: PreparedSheetSource) -> Bool {
        let comparison = lhs.prepared.bundleName.localizedStandardCompare(rhs.prepared.bundleName)
        if comparison != .orderedSame { return comparison == .orderedAscending }
        return lhs.source.packageURL.path < rhs.source.packageURL.path
    }
}

struct PreparedSheetSource: Sendable, Equatable {
    let source: SheetSource
    let prepared: PreparedSheetExport
}

struct PreparedSheetExport: Sendable, Equatable {
    let sheet: UlyssesSheet
    let rendered: RenderedSheet
    let bundleName: String
    let dates: SheetDates
    let roles: Set<UlyssesRole>
    let isGlued: Bool
    let isFavorite: Bool

    var noteTitle: String {
        rendered.title.isEmpty ? bundleName : rendered.title
    }
}

enum UlyssesRole: String, Sendable, Comparable {
    case archive
    case template
    case trash

    static func < (lhs: UlyssesRole, rhs: UlyssesRole) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct SheetOrderEntry: Sendable, Equatable {
    let sourcePackageURL: URL
    let sourcePackageName: String
    let sourceGroupURL: URL
    let sourceGroupPath: [String]
    let groupPath: [String]
    let title: String
    let destinationName: String
    let favorite: Bool
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

struct TextBundleWriter {
    func writeBundle(
        named name: String,
        markdown: String,
        media: [ReferencedMedia] = [],
        in destinationDirectory: URL,
        dates: SheetDates
    ) throws -> URL {
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let bundleURL = destinationDirectory
            .appendingPathComponent(sanitizedFileName(name))
            .appendingPathExtension("textbundle")
        guard !FileManager.default.fileExists(atPath: bundleURL.path) else {
            throw ExportError.destinationCollision(bundleURL.path)
        }
        try FileManager.default.createDirectory(
            at: bundleURL.appendingPathComponent("assets"),
            withIntermediateDirectories: true
        )
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
        return bundleURL
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
            "## What FSNotes Cannot Model Directly",
            "",
            "- Ulysses inspector/sidebar UI placement",
            "- Ulysses group icons, colors, goals, and activity tracking as native FSNotes folder settings",
            "- Ulysses favorites as native FSNotes pins; favorites are tagged and listed in the migration companion instead",
            "",
            "## Finish In FSNotes",
            "",
            "1. In FSNotes Settings > General, select the export folder as Default Storage. Do not merely add it as an external folder.",
            "2. In FSNotes Settings > Advanced, verify that Trash points to `<export folder>/Trash`, especially if FSNotes previously used a custom Trash location.",
            "3. Restart FSNotes and confirm that Ulysses Inbox sheets appear in Inbox and \(summary.trashSheets) deleted Ulysses sheets appear in Trash.",
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

struct UlyssesSheet: Sendable, Equatable {
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

indirect enum XMLNode: Sendable, Equatable {
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

struct RenderedSheet: Sendable, Equatable {
    var title: String
    var markdown: String
    var media: [ReferencedMedia]
    var summary: ExportSummary
}

struct ReferencedMedia: Sendable, Equatable {
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

        if !context.footnotes.isEmpty {
            sections.append(context.footnotes.joined(separator: "\n\n"))
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

        if let kind = paragraphKind(in: children) {
            let inlineNodes = children.first?.elementName == "tags" ? Array(children.dropFirst()) : children
            let content = inlineNodes.map { renderInline($0, context: &context) }.joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            switch kind {
            case "codeblock", "nativeblock":
                let fence = content.contains("```") ? "````" : "```"
                return "\(fence)\n\(content)\n\(fence)"
            case "comment":
                return "> **Ulysses comment:** \(content)"
            default:
                break
            }
        }

        let (prefix, inlineNodes) = paragraphPrefix(children)
        let content = inlineNodes.map { renderInline($0, context: &context) }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if prefix.isEmpty, content.isEmpty {
            return nil
        }

        return prefix + content
    }

    private func paragraphKind(in children: [XMLNode]) -> String? {
        guard let first = children.first,
              case .element("tags", _, let tagNodes) = first else { return nil }
        for tag in tagNodes {
            if case .element("tag", let attributes, _) = tag, let kind = attributes["kind"] {
                return kind
            }
        }
        return nil
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
            return "\(body) **[Ulysses annotation: \(annotation)]**"
        case "code":
            return "`\(elementBody(children, context: &context))`"
        case "inlineComment", "comment":
            let comment = elementBody(children, context: &context).trimmingCharacters(in: .whitespacesAndNewlines)
            return "**[Ulysses comment: \(comment)]**"
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
            let text = attributeMarkdown("text", in: children, context: &context)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return context.recordFootnote(text.isEmpty ? "Ulysses footnote with no text" : text)
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

    private func attributeMarkdown(_ identifier: String, in children: [XMLNode], context: inout RenderContext) -> String {
        for child in children {
            guard case .element("attribute", let attributes, let attributeChildren) = child,
                  attributes["identifier"] == identifier else { continue }
            return attributeChildren.map { node in
                if case .element("string", _, let stringChildren) = node {
                    return renderBlockNodes(stringChildren, context: &context)
                }
                return renderInline(node, context: &context)
            }.joined()
        }
        return ""
    }

    private func title(from markdown: String) -> String {
        for line in markdown.split(separator: "\n") {
            var title = line.trimmingCharacters(in: .whitespacesAndNewlines)
            title = title.replacingOccurrences(of: "!\\[([^]]*)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
            title = title.replacingOccurrences(of: "\\[([^]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
            title = title.replacingOccurrences(of: "^#{1,6}\\s+", with: "", options: .regularExpression)
            title = title.replacingOccurrences(of: "[*_~=`]", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { return title }
        }
        return ""
    }
}

struct RenderContext {
    let mediaResolver: MediaResolver
    var media: [ReferencedMedia] = []
    var mediaByDestination: Set<String> = []
    var summary = ExportSummary()
    var footnotes: [String] = []

    mutating func recordFootnote(_ text: String) -> String {
        let identifier = "ulysses-\(footnotes.count + 1)"
        let definition = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { $0.offset == 0 ? "[^\(identifier)]: \($0.element)" : "    \($0.element)" }
            .joined(separator: "\n")
        footnotes.append(definition)
        return "[^\(identifier)]"
    }

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
    let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "#%?[]()"))
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
