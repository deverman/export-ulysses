import Foundation

public enum ExportUlyssesVersion {
    public static let current = "1.0.0"
    public static let fingerprintSchema = 1
}

public struct BackupFingerprint: Sendable, Equatable, Codable {
    public var schemaVersion = ExportUlyssesVersion.fingerprintSchema
    public var sheetPackages = 0
    public var readableContentFiles = 0
    public var malformedContentFiles = 0
    public var plistFiles = 0
    public var readablePlistFiles = 0
    public var malformedPlistFiles = 0
    public var malformedPlistKinds: [String: Int] = [:]
    public var malformedPlistPaths: [String] = []
    public var rootElements: [String: Int] = [:]
    public var topLevelElements: [String: Int] = [:]
    public var attachmentTypes: [String: Int] = [:]
    public var markupIdentifiers: [String: Int] = [:]
    public var markupVersions: [String: Int] = [:]
    public var markupDefinitions: [String: Int] = [:]
    public var elementKinds: [String: Int] = [:]
    public var paragraphKinds: [String: Int] = [:]
    public var attributeIdentifiers: [String: Int] = [:]
    public var plistKeys: [String: Int] = [:]
    public var plistValueTypes: [String: Int] = [:]
    public var plistRootTypes: [String: Int] = [:]
    public var storeFormatVersions: [String: Int] = [:]
    public var packageExtensions: [String: Int] = [:]
    public var contentFileNames: [String: Int] = [:]
    public var storagePackageExtensions: [String: Int] = [:]

    mutating func record(_ key: String, in values: inout [String: Int]) {
        values[key, default: 0] += 1
    }
}

public struct FormatCompatibility: Sendable, Equatable, Codable {
    public let verified: Bool
    public let formatName: String
    public let errors: [String]
    public let warnings: [String]
}

public protocol UlyssesFormatReader {
    func supports(_ fingerprint: BackupFingerprint) -> Bool
    func readLibrary(in inputURL: URL) throws -> UlyssesLibrarySnapshot
}

public struct Ulysses40Format {
    public static let name = "Ulysses 40 backup (build 83290)"
    static let roots: Set<String> = ["sheet"]
    static let topLevel: Set<String> = ["string", "setting", "attachment", "markup"]
    static let attachments: Set<String> = ["note", "file", "keywords"]
    static let storeVersions: Set<String> = ["1"]
    static let markupIdentifiers: Set<String> = ["markdownxl"]
    static let markupVersions: Set<String> = ["1", "2", "3"]

    public static func evaluate(_ fingerprint: BackupFingerprint) -> FormatCompatibility {
        var errors: [String] = []
        var warnings: [String] = []

        if fingerprint.sheetPackages == 0 {
            errors.append("No .ulysses sheet packages were found.")
        }
        if fingerprint.sheetPackages != fingerprint.readableContentFiles {
            errors.append("Found \(fingerprint.sheetPackages) .ulysses packages but only \(fingerprint.readableContentFiles) readable Content.xml files.")
        }
        if fingerprint.malformedContentFiles > 0 {
            errors.append("\(fingerprint.malformedContentFiles) Content.xml files are malformed.")
        }
        if fingerprint.plistFiles != fingerprint.readablePlistFiles || fingerprint.malformedPlistFiles > 0 {
            warnings.append("\(fingerprint.malformedPlistFiles) optional metadata plist files are unreadable; affected paths are retained in the private migration report.")
        }
        let unexpectedPlistRoots = fingerprint.plistRootTypes.keys.filter { !$0.hasSuffix(":dictionary") }
        if !unexpectedPlistRoots.isEmpty {
            errors.append("Known plist files changed root type: \(unexpectedPlistRoots.sorted().joined(separator: ", ")).")
        }

        let unknownRoots = Set(fingerprint.rootElements.keys).subtracting(roots)
        if !unknownRoots.isEmpty {
            errors.append("Unknown XML root elements: \(unknownRoots.sorted().joined(separator: ", ")).")
        }
        let unknownTopLevel = Set(fingerprint.topLevelElements.keys).subtracting(topLevel)
        if !unknownTopLevel.isEmpty {
            errors.append("Unknown top-level sheet elements: \(unknownTopLevel.sorted().joined(separator: ", ")).")
        }
        let unknownAttachments = Set(fingerprint.attachmentTypes.keys).subtracting(attachments)
        if !unknownAttachments.isEmpty {
            errors.append("Unknown attachment types: \(unknownAttachments.sorted().joined(separator: ", ")).")
        }
        let unknownMarkupIdentifiers = Set(fingerprint.markupIdentifiers.keys).subtracting(markupIdentifiers)
        if !unknownMarkupIdentifiers.isEmpty {
            errors.append("Unknown markup identifiers: \(unknownMarkupIdentifiers.sorted().joined(separator: ", ")).")
        }
        let unknownMarkupVersions = Set(fingerprint.markupVersions.keys).subtracting(markupVersions)
        if !unknownMarkupVersions.isEmpty {
            errors.append("Unknown markup versions: \(unknownMarkupVersions.sorted().joined(separator: ", ")).")
        }

        let versions = Set(fingerprint.storeFormatVersions.keys)
        if versions.isEmpty {
            errors.append("No numeric storeFormatVersion was found in Info.ulgroup metadata.")
        } else if !versions.isSubset(of: storeVersions) {
            errors.append("Unknown storeFormatVersion values: \(versions.subtracting(storeVersions).sorted().joined(separator: ", ")).")
        }

        let incompatiblePlistTypes = fingerprint.plistValueTypes.keys.filter { entry in
            let parts = entry.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return false }
            switch parts[0] {
            case "displayName", "DisplayName", "name", "userIconName", "userTintColor":
                return parts[1] != "string"
            case "storeFormatVersion":
                return parts[1] != "number"
            case "childOrder", "sheetClusters", "order":
                return parts[1] != "array"
            case "activityTracking":
                return !["array", "dictionary"].contains(parts[1])
            case "countingGoal", "query", "versioning", "resolutionData":
                return parts[1] != "dictionary"
            default:
                return false
            }
        }
        if !incompatiblePlistTypes.isEmpty {
            errors.append("Known plist keys changed type: \(incompatiblePlistTypes.sorted().joined(separator: ", ")).")
        }

        if fingerprint.storagePackageExtensions.keys.contains(where: { $0 != "ulstoragebackup" }) {
            warnings.append("Unexpected storage package extensions were found and may represent a new Ulysses store type.")
        }

        return FormatCompatibility(
            verified: errors.isEmpty,
            formatName: name,
            errors: errors,
            warnings: warnings
        )
    }
}

public struct UlyssesBackupLocator {
    public init() {}

    public func newestBackup() throws -> URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/X5AZV975AG.com.soulmen.shared/Ulysses/Backups", isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ExportError.backupDiscoveryFailed(directory.path)
        }
        let backups = urls.filter { url in
            url.pathExtension == "ulbackup"
                && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        guard let newest = backups.max(by: { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left < right
        }) else {
            throw ExportError.backupDiscoveryFailed(directory.path)
        }
        return newest
    }
}

struct BackupFingerprintScanner {
    func scan(_ root: URL) throws -> BackupFingerprint {
        var fingerprint = BackupFingerprint()
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return fingerprint }

        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
               FileManager.default.fileExists(atPath: url.appendingPathComponent("Content/Info.ulgroup").path) {
                fingerprint.storagePackageExtensions[url.pathExtension.isEmpty ? "<none>" : url.pathExtension, default: 0] += 1
            }
            if url.pathExtension == "ulysses" {
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                guard isDirectory else { continue }
                fingerprint.sheetPackages += 1
                fingerprint.packageExtensions[url.pathExtension, default: 0] += 1
                let content = url.appendingPathComponent("Content.xml")
                fingerprint.contentFileNames[content.lastPathComponent, default: 0] += 1
                if FileManager.default.isReadableFile(atPath: content.path) {
                    fingerprint.readableContentFiles += 1
                    let scanner = SheetSchemaScanner()
                    if scanner.scan(content) {
                        fingerprint.merge(scanner.fingerprint)
                    } else {
                        fingerprint.malformedContentFiles += 1
                    }
                }
                enumerator.skipDescendants()
                continue
            }
            if ["Info.ulgroup", "Info.ulfilter", "favorites"].contains(url.lastPathComponent) {
                fingerprint.plistFiles += 1
                if scanPlist(url, into: &fingerprint) {
                    fingerprint.readablePlistFiles += 1
                } else {
                    fingerprint.malformedPlistFiles += 1
                    fingerprint.malformedPlistKinds[url.lastPathComponent, default: 0] += 1
                    let rootPath = root.standardizedFileURL.path
                    let path = url.standardizedFileURL.path
                    fingerprint.malformedPlistPaths.append(
                        path.hasPrefix(rootPath + "/") ? String(path.dropFirst(rootPath.count + 1)) : url.lastPathComponent
                    )
                }
            }
        }
        return fingerprint
    }

    private func scanPlist(_ url: URL, into fingerprint: inout BackupFingerprint) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let value = try? PropertyListSerialization.propertyList(from: data, format: nil)
        else { return false }
        fingerprint.plistRootTypes["\(url.lastPathComponent):\(plistType(value))", default: 0] += 1
        guard let dictionary = value as? [String: Any] else { return true }
        for (key, child) in dictionary {
            scanPlistValue(child, keyPath: key, into: &fingerprint)
        }
        return true
    }

    private func scanPlistValue(_ value: Any, keyPath: String, into fingerprint: inout BackupFingerprint) {
        fingerprint.plistKeys[keyPath, default: 0] += 1
        fingerprint.plistValueTypes["\(keyPath):\(plistType(value))", default: 0] += 1
        if keyPath == "storeFormatVersion", let number = value as? NSNumber {
                fingerprint.storeFormatVersions[number.stringValue, default: 0] += 1
        }
        if let dictionary = value as? [String: Any] {
            for (childKey, childValue) in dictionary {
                scanPlistValue(childValue, keyPath: "\(keyPath).\(childKey)", into: &fingerprint)
            }
        }
    }

    private func plistType(_ value: Any) -> String {
        switch value {
        case is String: "string"
        case is [Any]: "array"
        case is [String: Any]: "dictionary"
        case is Date: "date"
        case is Data: "data"
        case is NSNumber: "number"
        default: String(describing: type(of: value))
        }
    }
}

private extension BackupFingerprint {
    mutating func merge(_ other: BackupFingerprint) {
        for (key, count) in other.rootElements { rootElements[key, default: 0] += count }
        for (key, count) in other.topLevelElements { topLevelElements[key, default: 0] += count }
        for (key, count) in other.attachmentTypes { attachmentTypes[key, default: 0] += count }
        for (key, count) in other.markupIdentifiers { markupIdentifiers[key, default: 0] += count }
        for (key, count) in other.markupVersions { markupVersions[key, default: 0] += count }
        for (key, count) in other.markupDefinitions { markupDefinitions[key, default: 0] += count }
        for (key, count) in other.elementKinds { elementKinds[key, default: 0] += count }
        for (key, count) in other.paragraphKinds { paragraphKinds[key, default: 0] += count }
        for (key, count) in other.attributeIdentifiers { attributeIdentifiers[key, default: 0] += count }
    }
}

private final class SheetSchemaScanner: NSObject, XMLParserDelegate {
    var fingerprint = BackupFingerprint()
    private var stack: [String] = []
    private var valid = true

    func scan(_ url: URL) -> Bool {
        guard let parser = XMLParser(contentsOf: url) else { return false }
        parser.delegate = self
        return parser.parse() && valid
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        valid = false
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if stack.isEmpty {
            fingerprint.rootElements[elementName, default: 0] += 1
        } else if stack == ["sheet"] {
            fingerprint.topLevelElements[elementName, default: 0] += 1
            if elementName == "attachment" {
                fingerprint.attachmentTypes[attributeDict["type"] ?? "<missing>", default: 0] += 1
            } else if elementName == "markup" {
                fingerprint.markupIdentifiers[attributeDict["identifier"] ?? "<missing>", default: 0] += 1
                fingerprint.markupVersions[attributeDict["version"] ?? "<missing>", default: 0] += 1
            }
        }
        if stack.last == "markup", elementName == "tag" {
            fingerprint.markupDefinitions[attributeDict["definition"] ?? "<missing>", default: 0] += 1
        }
        if elementName == "element", let kind = attributeDict["kind"] {
            fingerprint.elementKinds[kind, default: 0] += 1
        }
        if elementName == "paragraph", let kind = attributeDict["kind"] {
            fingerprint.paragraphKinds[kind, default: 0] += 1
        }
        if elementName == "attribute", let identifier = attributeDict["identifier"] {
            fingerprint.attributeIdentifiers[identifier, default: 0] += 1
        }
        stack.append(elementName)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if stack.last == elementName { stack.removeLast() }
    }
}
