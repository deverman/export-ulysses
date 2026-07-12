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

public struct ExportProgress: Sendable, Equatable {
    public let phase: String
    public let completed: Int
    public let total: Int
}

public struct Exporter: Sendable {
    private let verbose: Bool
    private let maxConcurrentExports: Int
    private let progress: (@Sendable (ExportProgress) -> Void)?

    public init(
        verbose: Bool = false,
        maxConcurrentExports: Int = 2,
        progress: (@Sendable (ExportProgress) -> Void)? = nil
    ) {
        self.verbose = verbose
        self.maxConcurrentExports = max(1, maxConcurrentExports)
        self.progress = progress
    }

    public func run(input: String, output: String, allowUnknownFormat: Bool = false, commandLine: [String] = []) async throws -> ExportSummary {
        let inputURL = URL(fileURLWithPath: input)
        let outputURL = URL(fileURLWithPath: output)
        try requireEmptyOutput(outputURL)
        let snapshot = try readSnapshot(inputURL, allowUnknownFormat: allowUnknownFormat)
        let sheets = snapshot.sheets

        guard !sheets.isEmpty else {
            throw ExportError.noSheetsFound(inputURL.path)
        }

        if verbose {
            print("Found \(sheets.count) Ulysses sheets.")
        }

        let mediaIndex = MediaIndex(sheets: sheets)
        let sheetOrderIndex = SheetOrderIndex(sheets: sheets)
        let groupPathResolver = MigrationLayout(sheets: sheets, groups: snapshot.groups)
        return try await OutputTransaction(destination: outputURL).perform({ stagingURL in
            try await export(snapshot, to: stagingURL, mediaIndex: mediaIndex, sheetOrderIndex: sheetOrderIndex, groupPathResolver: groupPathResolver, commandLine: commandLine)
        }, validate: { stagingURL, summary in
            try OutputValidator().validate(root: stagingURL, summary: summary, snapshot: snapshot)
        })
    }

    public func analyze(input: String, allowUnknownFormat: Bool = false, commandLine: [String] = []) async throws -> ExportAnalysis {
        let inputURL = URL(fileURLWithPath: input)
        let snapshot = try readSnapshot(inputURL, allowUnknownFormat: allowUnknownFormat)
        guard !snapshot.sheets.isEmpty else {
            throw ExportError.noSheetsFound(inputURL.path)
        }

        let mediaIndex = MediaIndex(sheets: snapshot.sheets)
        let sheetOrderIndex = SheetOrderIndex(sheets: snapshot.sheets)
        let groupPathResolver = MigrationLayout(sheets: snapshot.sheets, groups: snapshot.groups)
        return try await analyze(snapshot, mediaIndex: mediaIndex, sheetOrderIndex: sheetOrderIndex, groupPathResolver: groupPathResolver, commandLine: commandLine)
    }

    public func doctor(input: String, output: String?, allowUnknownFormat: Bool = false, commandLine: [String] = []) async -> PreflightResult {
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

        checks.append(PreflightCheck(
            name: "External Folders",
            status: .warning,
            message: "Ulysses backups do not include External Folders. Export or copy those folders separately before leaving Ulysses."
        ))

        if let output {
            let outputURL = URL(fileURLWithPath: output)
            checks.append(outputCheck(for: outputURL, inputURL: inputURL))
            checks.append(capacityCheck(inputURL: inputURL, outputURL: outputURL))
        } else {
            checks.append(PreflightCheck(name: "Output folder", status: .warning, message: "No output folder was provided; doctor can only validate the input and dry-run analysis."))
        }

        do {
            let analysis = try await analyze(input: input, allowUnknownFormat: allowUnknownFormat, commandLine: commandLine)
            let compatibility = try Ulysses40BackupReader().readLibrary(in: inputURL).compatibility
            checks.append(PreflightCheck(
                name: "Ulysses format",
                status: compatibility.verified ? .success : .warning,
                message: compatibility.verified
                    ? "Verified against \(compatibility.formatName)."
                    : "Unverified format accepted only because --allow-unknown-format was supplied."
            ))
            for warning in compatibility.warnings {
                checks.append(PreflightCheck(name: "Format metadata", status: .warning, message: warning))
            }
            checks.append(PreflightCheck(name: "Sheet discovery", status: .success, message: "Found \(analysis.summary.sheets) sheets."))
            if analysis.summary.trashSheets > 0 {
                checks.append(PreflightCheck(
                    name: "FSNotes Trash",
                    status: .warning,
                    message: "\(analysis.summary.trashSheets) Ulysses Trash sheets will be written to <output>/Trash. For an existing FSNotes library, move those TextBundles into its configured Trash; for a new library, configure FSNotes Trash to use that folder."
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

    private func readSnapshot(_ inputURL: URL, allowUnknownFormat: Bool) throws -> UlyssesLibrarySnapshot {
        let snapshot = try Ulysses40BackupReader().readLibrary(in: inputURL)
        guard snapshot.compatibility.verified || allowUnknownFormat else {
            throw ExportError.unverifiedFormat(snapshot.compatibility.errors)
        }
        return snapshot
    }

    private func export(_ snapshot: UlyssesLibrarySnapshot, to outputURL: URL, mediaIndex: MediaIndex, sheetOrderIndex: SheetOrderIndex, groupPathResolver: MigrationLayout, commandLine: [String]) async throws -> ExportSummary {
        let sheetExporter = SheetExporter(
            mediaIndex: mediaIndex,
            sheetOrderIndex: sheetOrderIndex,
            favoriteSheetPaths: snapshot.favoriteSheetPaths,
            groupPathResolver: groupPathResolver
        )
        let prepared = try await process(snapshot.sheets, phase: "Parsing sheets") { try sheetExporter.prepare($0) }
        let names = OutputNameResolver(prepared: prepared, groupPaths: groupPathResolver)
        let results = try await process(prepared, phase: "Writing TextBundles") { item in
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

    private func analyze(_ snapshot: UlyssesLibrarySnapshot, mediaIndex: MediaIndex, sheetOrderIndex: SheetOrderIndex, groupPathResolver: MigrationLayout, commandLine: [String]) async throws -> ExportAnalysis {
        let sheetExporter = SheetExporter(
            mediaIndex: mediaIndex,
            sheetOrderIndex: sheetOrderIndex,
            favoriteSheetPaths: snapshot.favoriteSheetPaths,
            groupPathResolver: groupPathResolver
        )
        let prepared = try await process(snapshot.sheets, phase: "Analyzing sheets") { try sheetExporter.prepare($0) }
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
        phase: String,
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
                let completed = results.count
                if completed == inputs.count || completed % 100 == 0 {
                    progress?(ExportProgress(phase: phase, completed: completed, total: inputs.count))
                }
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

    private func outputCheck(for outputURL: URL, inputURL: URL) -> PreflightCheck {
        let standardized = outputURL.standardizedFileURL
        let forbidden = [URL(fileURLWithPath: "/").standardizedFileURL.path, FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path]
        if forbidden.contains(standardized.path) || standardized.path.hasPrefix(inputURL.standardizedFileURL.path + "/") {
            return PreflightCheck(name: "Output folder", status: .failure, message: "Refusing unsafe destination \(standardized.path). Choose a new dedicated folder outside the backup.")
        }
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

    private func capacityCheck(inputURL: URL, outputURL: URL) -> PreflightCheck {
        var sourceBytes: Int64 = 0
        if let enumerator = FileManager.default.enumerator(
            at: inputURL,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
                sourceBytes += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
            }
        }
        var probe = outputURL.deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: probe.path), probe.path != "/" {
            probe.deleteLastPathComponent()
        }
        let available = (try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? 0
        let required = max(sourceBytes * 2, 100 * 1_024 * 1_024)
        if available > required {
            return PreflightCheck(name: "Free disk space", status: .success, message: "At least \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) is available; estimated requirement is \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)).")
        }
        return PreflightCheck(name: "Free disk space", status: .failure, message: "Only \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) is available. Free at least \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)) before migrating.")
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
    case unverifiedFormat([String])
    case backupDiscoveryFailed(String)
    case validationFailed(String)

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
        case .unverifiedFormat(let reasons):
            "This backup does not match the verified Ulysses 40 format. \(reasons.joined(separator: " ")) Run `export-ulysses doctor` and attach its anonymous support JSON. Developers may inspect with --allow-unknown-format, but should not trust that export without validation."
        case .backupDiscoveryFailed(let path):
            "No Ulysses backup was found in \(path). In Ulysses choose Settings > Backup > Backup now, then rerun this command. You can also choose File > Browse Backups or pass --backup with an exported .ulbackup path."
        case .validationFailed(let reason):
            "The staged migration failed validation and was not published. \(reason) Run `export-ulysses doctor` and attach the anonymous support JSON when reporting this problem."
        }
    }
}
