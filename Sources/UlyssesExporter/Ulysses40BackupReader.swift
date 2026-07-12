import Foundation

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
    public let fingerprint: BackupFingerprint
    public let compatibility: FormatCompatibility
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

public struct Ulysses40BackupReader: UlyssesFormatReader {
    public init() {}

    public func supports(_ fingerprint: BackupFingerprint) -> Bool {
        Ulysses40Format.evaluate(fingerprint).verified
    }

    public func readLibrary(in inputURL: URL) throws -> UlyssesLibrarySnapshot {
        let root = inputURL.standardizedFileURL
        let fingerprint = try BackupFingerprintScanner().scan(root)
        let compatibility = Ulysses40Format.evaluate(fingerprint)
        let sheets = try findSheets(in: root)
        let groups = findGroups(in: root)
        return UlyssesLibrarySnapshot(
            rootURL: root,
            sheets: sheets,
            groups: groups,
            favoriteSheetPaths: findFavoriteSheetPaths(in: root),
            filters: findFilters(in: root),
            fingerprint: fingerprint,
            compatibility: compatibility
        )
    }

    func findSheets(in inputURL: URL) throws -> [SheetSource] {
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
            sheets.append(SheetSource(packageURL: url, contentURL: contentURL, groupURL: url.deletingLastPathComponent(), groupPath: sourceGroupPath))
            enumerator.skipDescendants()
        }
        return sheets
    }

    private func findGroups(in inputURL: URL) -> [GroupSource] {
        guard let enumerator = FileManager.default.enumerator(
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
            guard !groupPath.isEmpty else { continue }
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

    private func findFilters(in root: URL) -> [UlyssesFilter] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var filters: [UlyssesFilter] = []
        for case let url as URL in enumerator where url.lastPathComponent == "Info.ulfilter" {
            let filterURL = url.deletingLastPathComponent()
            let sourcePath = groupPath(forDirectoryAt: filterURL.deletingLastPathComponent(), root: root)
            guard let data = try? Data(contentsOf: url),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { continue }

            let name = plist["displayName"] as? String
                ?? filterURL.lastPathComponent.replacingOccurrences(of: "-ulfilter", with: "")
            let query = plist["query"].map(Self.describePlist) ?? "Unavailable"
            filters.append(UlyssesFilter(
                name: name,
                groupPath: sourcePath,
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
