import Foundation

public struct ExportSummary: Sendable, Equatable {
    public var sheets = 0
    public var sidebarNotes = 0
    public var fileAttachments = 0
    public var inlineImages = 0
    public var keywords = 0
    public var materialSheets = 0
    public var missingMedia = 0
    public var recoveredMedia = 0
    public var unsupportedNodes = 0
    public var unsupportedDetails: [String: Int] = [:]

    public mutating func add(_ other: ExportSummary) {
        sheets += other.sheets
        sidebarNotes += other.sidebarNotes
        fileAttachments += other.fileAttachments
        inlineImages += other.inlineImages
        keywords += other.keywords
        materialSheets += other.materialSheets
        missingMedia += other.missingMedia
        recoveredMedia += other.recoveredMedia
        unsupportedNodes += other.unsupportedNodes
        for (key, value) in other.unsupportedDetails {
            unsupportedDetails[key, default: 0] += value
        }
    }

    public mutating func recordUnsupported(_ key: String) {
        unsupportedNodes += 1
        unsupportedDetails[key, default: 0] += 1
    }
}

public struct Exporter {
    private let verbose: Bool
    private let maxConcurrentExports: Int

    public init(verbose: Bool = false, maxConcurrentExports: Int = 2) {
        self.verbose = verbose
        self.maxConcurrentExports = max(1, maxConcurrentExports)
    }

    public func run(input: String, output: String, keepGroups: Bool, ignoring ignoredGroups: [String]) async throws -> ExportSummary {
        let inputURL = URL(fileURLWithPath: input)
        let outputURL = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

        let sheets = try UlyssesBackupReader().findSheets(
            in: inputURL,
            keepGroups: keepGroups,
            ignoring: Set(ignoredGroups)
        )

        guard !sheets.isEmpty else {
            throw ExportError.noSheetsFound(inputURL.path)
        }

        if verbose {
            print("Found \(sheets.count) Ulysses sheets.")
        }

        let mediaIndex = MediaIndex(sheets: sheets)
        return try await export(sheets, to: outputURL, mediaIndex: mediaIndex)
    }

    private func export(_ sheets: [SheetSource], to outputURL: URL, mediaIndex: MediaIndex) async throws -> ExportSummary {
        try await withThrowingTaskGroup(of: ExportSummary.self) { group in
            var nextSheetIndex = 0

            func enqueueNextSheet() {
                guard nextSheetIndex < sheets.count else { return }
                let sheet = sheets[nextSheetIndex]
                nextSheetIndex += 1
                group.addTask {
                    try SheetExporter(mediaIndex: mediaIndex).export(sheet, to: outputURL)
                }
            }

            for _ in 0..<min(maxConcurrentExports, sheets.count) {
                enqueueNextSheet()
            }

            var summary = ExportSummary()
            var exported = 0
            for try await sheetSummary in group {
                exported += 1
                summary.add(sheetSummary)
                enqueueNextSheet()
                if verbose, exported % 100 == 0 {
                    print("Exported \(exported) sheets.")
                }
            }
            return summary
        }
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
    public let groupPath: [String]
}

struct UlyssesBackupReader {
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

            let groupPath = keepGroups ? groupPath(for: url, root: root, ignoring: ignoredGroups) : []
            if groupPath.contains(where: ignoredGroups.contains) {
                enumerator.skipDescendants()
                continue
            }

            sheets.append(SheetSource(packageURL: url, contentURL: contentURL, groupPath: groupPath))
            enumerator.skipDescendants()
        }
        return sheets
    }

    private func groupPath(for sheetURL: URL, root: URL, ignoring ignoredGroups: Set<String>) -> [String] {
        let rootPath = root.standardizedFileURL.path
        let parentPath = sheetURL.deletingLastPathComponent().standardizedFileURL.path
        let relativePath: String
        if parentPath == rootPath {
            relativePath = ""
        } else if parentPath.hasPrefix(rootPath + "/") {
            relativePath = String(parentPath.dropFirst(rootPath.count + 1))
        } else {
            relativePath = sheetURL.deletingLastPathComponent().lastPathComponent
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

    private func displayName(forGroupAt url: URL) -> String? {
        let infoURL = url.appendingPathComponent("Info.ulgroup")
        guard let data = try? Data(contentsOf: infoURL),
              let dictionary = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return nil
        }
        return dictionary["DisplayName"] as? String
            ?? dictionary["displayName"] as? String
            ?? dictionary["name"] as? String
    }
}

struct SheetExporter {
    let mediaIndex: MediaIndex

    func export(_ source: SheetSource, to outputRoot: URL) throws -> ExportSummary {
        let data = try readDataWithRetry(from: source.contentURL)
        var sheet = try UlyssesSheetParser(contentURL: source.contentURL).parse(data)
        sheet.migrationTags.append(contentsOf: migrationTags(for: source, sheet: sheet))
        let renderer = MarkdownRenderer(mediaResolver: MediaResolver(packageURL: source.packageURL, mediaIndex: mediaIndex))
        let rendered = renderer.render(sheet)

        var summary = rendered.summary
        summary.sheets = 1
        summary.sidebarNotes = sheet.sidebarNotes.count
        summary.fileAttachments = sheet.fileAttachmentIDs.count
        summary.keywords = sheet.keywords.count
        summary.materialSheets = sheet.isMaterial ? 1 : 0

        let bundleName = sanitizedFileName(rendered.title.isEmpty ? source.packageURL.deletingPathExtension().lastPathComponent : rendered.title)
        var destinationDirectory = outputRoot
        for group in source.groupPath {
            destinationDirectory.appendPathComponent(sanitizedFileName(group))
        }
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let dates = sheetDates(for: source)

        let bundleURL = try DestinationAllocator.shared.createBundle(
            at: destinationDirectory.appendingPathComponent(bundleName).appendingPathExtension("textbundle")
        )

        let textURL = bundleURL.appendingPathComponent("text.markdown")
        let infoURL = bundleURL.appendingPathComponent("info.json")
        let assetsURL = bundleURL.appendingPathComponent("assets")
        try rendered.markdown.write(to: textURL, atomically: true, encoding: .utf8)
        try infoJSON(for: dates).write(to: infoURL, atomically: true, encoding: .utf8)

        for media in rendered.media {
            let destination = assetsURL.appendingPathComponent(media.destinationName)
            if let sourceURL = media.sourceURL {
                if FileManager.default.fileExists(atPath: sourceURL.path) {
                    try FileManager.default.copyItem(at: sourceURL, to: destination)
                } else {
                    summary.missingMedia += 1
                }
            }
        }

        try apply(dates: dates, to: [bundleURL, assetsURL, textURL, infoURL])
        return summary
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

    private func apply(dates: SheetDates, to urls: [URL]) throws {
        let attributes: [FileAttributeKey: Any] = [
            .creationDate: dates.created,
            .modificationDate: dates.modified
        ]
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
        }
    }

    private func infoJSON(for dates: SheetDates) -> String {
        let created = Int(dates.created.timeIntervalSince1970)
        let modified = Int(dates.modified.timeIntervalSince1970)
        return """
        {
          "version": 2,
          "type": "net.daringfireball.markdown",
          "created": \(created),
          "modified": \(modified)
        }
        """
    }

    private func migrationTags(for source: SheetSource, sheet: UlyssesSheet) -> [String] {
        var tags: [String] = []
        if sheet.isMaterial {
            tags.append("ulysses/material")
        }
        if source.groupPath.first?.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare("Archive") == .orderedSame {
            tags.append("ulysses/archive")
        }
        return tags
    }
}

struct SheetDates: Equatable {
    let created: Date
    let modified: Date
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
            context.summary.missingMedia += 1
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
                context.summary.missingMedia += 1
                return "![\(description)](\(url))"
            }
            context.summary.missingMedia += 1
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
    let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "#%?[]"))
    let escaped = destinationName.addingPercentEncoding(withAllowedCharacters: allowed) ?? destinationName
    return "assets/\(escaped)"
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
