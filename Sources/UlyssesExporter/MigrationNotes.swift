import Foundation

struct MigrationIndexCounts: Equatable {
    let orderNotes: Int
    let metadataNotes: Int
}

struct MigrationIndexWriter {
    let sheetOrderIndex: SheetOrderIndex
    let groupPathResolver: GroupPathResolver
    let outputURL: URL

    func write(entries: [SheetOrderEntry], groups: [GroupSource]) throws -> MigrationIndexCounts {
        let order = orderSections(for: entries)
        let metadata = metadataSections(for: groups, entries: entries)
        let directory = outputURL.appendingPathComponent("_Ulysses Migration", isDirectory: true)
        let dates = SheetDates(
            created: entries.map(\.dates.created).min() ?? Date(),
            modified: entries.map(\.dates.modified).max() ?? Date()
        )
        if !order.isEmpty {
            try writeNote(named: "Ulysses Library Map", tag: "#ulysses/order-index", sections: order, in: directory, dates: dates)
        }
        if !metadata.isEmpty {
            try writeNote(named: "Ulysses Group Metadata", tag: "#ulysses/group-metadata", sections: metadata, in: directory, dates: dates)
        }
        return MigrationIndexCounts(orderNotes: order.isEmpty ? 0 : 1, metadataNotes: metadata.isEmpty ? 0 : 1)
    }

    func counts(entries: [SheetOrderEntry], groups: [GroupSource]) -> MigrationIndexCounts {
        MigrationIndexCounts(
            orderNotes: orderSections(for: entries).isEmpty ? 0 : 1,
            metadataNotes: metadataSections(for: groups, entries: entries).isEmpty ? 0 : 1
        )
    }

    private func writeNote(named name: String, tag: String, sections: [[String]], in directory: URL, dates: SheetDates) throws {
        let markdown = (["# \(name)", "", tag, ""] + sections.flatMap { $0 + [""] }).joined(separator: "\n")
        _ = try TextBundleWriter().writeBundle(named: name, markdown: markdown, in: directory, dates: dates)
    }

    private func orderSections(for entries: [SheetOrderEntry]) -> [[String]] {
        Dictionary(grouping: entries, by: { $0.sourceGroupURL.standardizedFileURL.path }).values.compactMap { groupEntries in
            guard let first = groupEntries.first,
                  !first.groupPath.isEmpty,
                  let groupOrder = sheetOrderIndex.order(for: first.sourceGroupURL)
            else { return nil }
            let clusters = orderedEntries(groupEntries, using: groupOrder)
            guard clusters.flatMap({ $0 }).count > 1 else { return nil }
            var lines = ["## Ulysses Sheet Order: \(first.groupPath.joined(separator: " / "))", ""]
            if clusters.contains(where: { $0.count > 1 }) { lines += ["#ulysses/glued", ""] }
            for (index, cluster) in clusters.enumerated() {
                if cluster.count == 1 {
                    lines.append("\(index + 1). \(fsNotesLink(for: cluster[0], showFileName: true))")
                } else {
                    lines.append("\(index + 1). Glued sheets")
                    lines += cluster.map { "   - \(fsNotesLink(for: $0, showFileName: true))" }
                }
            }
            return lines
        }.sorted { $0.first! < $1.first! }
    }

    private func orderedEntries(_ entries: [SheetOrderEntry], using order: GroupSheetOrder) -> [[SheetOrderEntry]] {
        let byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.sourcePackageName, $0) })
        var included = Set<String>()
        var clusters = order.sheetClusters.compactMap { sourceCluster -> [SheetOrderEntry]? in
            let resolved = sourceCluster.compactMap { name -> SheetOrderEntry? in
                guard let entry = byName[name] else { return nil }
                included.insert(name)
                return entry
            }
            return resolved.isEmpty ? nil : resolved
        }
        clusters += entries.filter { !included.contains($0.sourcePackageName) }
            .sorted {
                let comparison = $0.title.localizedStandardCompare($1.title)
                return comparison == .orderedSame
                    ? $0.sourcePackageURL.path < $1.sourcePackageURL.path
                    : comparison == .orderedAscending
            }
            .map { [$0] }
        return clusters
    }

    private func metadataSections(for groups: [GroupSource], entries: [SheetOrderEntry]) -> [[String]] {
        groups.sorted { $0.relativePath < $1.relativePath }.compactMap { group in
            let roles = roles(for: group)
            guard group.metadata.hasUserVisibleMetadata || !roles.isEmpty else { return nil }
            var childNames = Dictionary(uniqueKeysWithValues: entries
                .filter { $0.sourceGroupURL.standardizedFileURL == group.groupURL.standardizedFileURL }
                .map { ($0.sourcePackageName, $0.title) })
            for child in groups where child.groupURL.deletingLastPathComponent().standardizedFileURL == group.groupURL.standardizedFileURL {
                childNames[child.groupURL.lastPathComponent] = child.metadata.displayName ?? child.groupPath.last ?? "Untitled group"
            }
            let outputPath = groupPathResolver.outputPath(for: group)
            var lines = ["## Ulysses Metadata: \(outputPath.joined(separator: " / "))", ""]
            if !roles.isEmpty { lines += [roles.sorted().map { "#ulysses/\($0.rawValue)" }.joined(separator: " "), ""] }
            if let icon = group.metadata.userIconName { lines.append("- Ulysses icon: \(icon)") }
            if let color = group.metadata.userTintColor { lines.append("- Ulysses color: \(color)") }
            if !roles.isEmpty { lines.append("- Ulysses role: \(roles.sorted().map(\.rawValue).joined(separator: ", "))") }
            if !group.metadata.countingGoal.isEmpty {
                lines += ["", "### Goal"] + group.metadata.countingGoal.sorted(by: { $0.key < $1.key }).map { "- \($0.key): \($0.value)" }
            }
            if group.metadata.activitySessionCount > 0 {
                lines += ["", "### Activity", "- Sessions recorded: \(group.metadata.activitySessionCount)"]
            }
            if !group.metadata.childOrder.isEmpty {
                lines += ["", "### Original Child Order"]
                lines += group.metadata.childOrder.enumerated().map { index, id in
                    "\(index + 1). \(childNames[id] ?? id) (`\(id)`)"
                }
            }
            return lines
        }
    }

    private func roles(for group: GroupSource) -> Set<UlyssesRole> {
        let components = group.groupURL.pathComponents.map { $0.lowercased() }
        var roles = Set<UlyssesRole>()
        if components.contains("trash-ultrash") { roles.insert(.trash) }
        if components.contains("templates-ulgroup") { roles.insert(.template) }
        if isUlyssesArchive(url: group.groupURL, groupPath: group.groupPath) {
            roles.insert(.archive)
        }
        return roles
    }
}

func fsNotesLink(for entry: SheetOrderEntry, showFileName: Bool = false) -> String {
    let title = entry.title.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    let fileName = entry.destinationName.replacingOccurrences(of: ".textbundle", with: "")
    let target = fileName.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? fileName
    let suffix = showFileName ? " (`\(entry.destinationName)`)" : ""
    return "[\(title)](fsnotes://find?id=\(target))\(suffix)"
}

struct LibraryCompanionWriter {
    let outputURL: URL
    let groupPathResolver: GroupPathResolver

    func write(snapshot: UlyssesLibrarySnapshot, entries: [SheetOrderEntry], summary: ExportSummary) throws {
        let migrationDirectory = outputURL.appendingPathComponent("_Ulysses Migration", isDirectory: true)
        let dates = SheetDates(created: Date(), modified: Date())
        let favorites = entries.filter(\.favorite).sorted {
            let comparison = $0.title.localizedStandardCompare($1.title)
            return comparison == .orderedSame
                ? $0.sourcePackageURL.path < $1.sourcePackageURL.path
                : comparison == .orderedAscending
        }
        if !favorites.isEmpty {
            let lines = ["# Ulysses Favorites", "", "#ulysses/favorite", "", "These sheets were marked as favorites in Ulysses.", ""]
                + favorites.map { "- \(fsNotesLink(for: $0))" } + [""]
            _ = try TextBundleWriter().writeBundle(named: "Ulysses Favorites", markdown: lines.joined(separator: "\n"), in: migrationDirectory, dates: dates)
        }

        if !snapshot.filters.isEmpty {
            var lines = ["# Ulysses Saved Filters", "", "#ulysses/saved-filters", ""]
            for filter in snapshot.filters.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
                lines += [
                    "## \(filter.name)", "",
                    "- Scope: \(filter.groupPath.isEmpty ? "Entire exported library" : filter.groupPath.joined(separator: " / "))",
                    "- Status: \(filter.isInTrash ? "Deleted in Ulysses Trash" : "Active")",
                    "- Query: \(filter.queryDescription)", ""
                ]
            }
            _ = try TextBundleWriter().writeBundle(named: "Ulysses Saved Filters", markdown: lines.joined(separator: "\n"), in: migrationDirectory, dates: dates)
        }
        try writeManifest(snapshot: snapshot, entries: entries, summary: summary)
    }

    private func writeManifest(snapshot: UlyssesLibrarySnapshot, entries: [SheetOrderEntry], summary: ExportSummary) throws {
        let manifest = MigrationManifest(
            version: 2,
            counts: summary,
            sheets: entries.sorted { $0.sourcePackageURL.path < $1.sourcePackageURL.path }.map {
                ManifestSheet(
                    ulyssesID: $0.sourcePackageURL.deletingPathExtension().lastPathComponent,
                    sourcePath: relativePath(for: $0.sourcePackageURL, root: snapshot.rootURL),
                    groupPath: $0.groupPath,
                    title: $0.title,
                    destinationName: $0.destinationName,
                    favorite: $0.favorite,
                    created: $0.dates.created,
                    modified: $0.dates.modified
                )
            },
            groups: snapshot.groups.sorted { $0.relativePath < $1.relativePath }.map {
                ManifestGroup(
                    sourcePath: $0.relativePath,
                    sourceGroupPath: $0.groupPath,
                    destinationGroupPath: groupPathResolver.outputPath(for: $0),
                    childOrder: $0.metadata.childOrder,
                    sheetClusters: $0.metadata.sheetClusters,
                    icon: $0.metadata.userIconName,
                    color: $0.metadata.userTintColor,
                    goal: $0.metadata.countingGoal
                )
            },
            filters: snapshot.filters.map {
                ManifestFilter(name: $0.name, groupPath: $0.groupPath, query: $0.queryDescription, trashed: $0.isInTrash)
            }
        )
        let directory = outputURL.appendingPathComponent(".export-ulysses", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
    }

    private func relativePath(for url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path.hasPrefix(rootPath + "/") ? String(path.dropFirst(rootPath.count + 1)) : path
    }
}

private struct MigrationManifest: Codable {
    let version: Int
    let counts: ExportSummary
    let sheets: [ManifestSheet]
    let groups: [ManifestGroup]
    let filters: [ManifestFilter]
}

private struct ManifestSheet: Codable {
    let ulyssesID: String
    let sourcePath: String
    let groupPath: [String]
    let title: String
    let destinationName: String
    let favorite: Bool
    let created: Date
    let modified: Date
}

private struct ManifestGroup: Codable {
    let sourcePath: String
    let sourceGroupPath: [String]
    let destinationGroupPath: [String]
    let childOrder: [String]
    let sheetClusters: [[String]]
    let icon: String?
    let color: String?
    let goal: [String: String]
}

private struct ManifestFilter: Codable {
    let name: String
    let groupPath: [String]
    let query: String
    let trashed: Bool
}
