import Foundation

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

func sanitizedFileName(_ name: String) -> String {
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
