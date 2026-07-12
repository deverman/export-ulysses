import Foundation

struct MigrationLayout: Sendable, Equatable {
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

    init(prepared: [PreparedSheetSource], groupPaths: MigrationLayout) {
        let allocationGroups = Dictionary(grouping: prepared) { item in
            if item.prepared.roles.contains(.trash) {
                return "trash/" + groupPaths.outputPath(for: item.source)
                    .map(sanitizedFileName)
                    .joined(separator: "/")
                    .lowercased()
            }
            return "fsnotes-searchable"
        }
        var resolved: [String: String] = [:]

        for (allocationGroup, items) in allocationGroups {
            let byRequestedName = Dictionary(grouping: items) { $0.prepared.bundleName.lowercased() }
            var used = allocationGroup == "fsnotes-searchable" ? Self.reservedCompanionNames : []
            var duplicates: [PreparedSheetSource] = []

            for group in byRequestedName.values {
                let sorted = group.sorted { $0.source.packageURL.path < $1.source.packageURL.path }
                guard let primary = sorted.first else { continue }
                if used.contains(primary.prepared.bundleName.lowercased()) {
                    duplicates.append(primary)
                } else {
                    resolved[primary.source.packageURL.standardizedFileURL.path] = primary.prepared.bundleName
                    used.insert(primary.prepared.bundleName.lowercased())
                }
                duplicates.append(contentsOf: sorted.dropFirst())
            }

            for item in duplicates.sorted(by: Self.allocationOrder) {
                let base = item.prepared.bundleName
                var counter = 1
                var candidate = disambiguatedFileName(base, counter: counter)
                while used.contains(candidate.lowercased()) {
                    counter += 1
                    candidate = disambiguatedFileName(base, counter: counter)
                }
                resolved[item.source.packageURL.standardizedFileURL.path] = candidate
                used.insert(candidate.lowercased())
            }
        }
        namesBySourcePath = resolved
    }

    private static let reservedCompanionNames: Set<String> = [
        "ulysses export report",
        "ulysses favorites",
        "ulysses group metadata",
        "ulysses library map",
        "ulysses saved filters"
    ]

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
