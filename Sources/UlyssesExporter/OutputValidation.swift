import Foundation

struct OutputTransaction {
    let destination: URL

    func perform<Result>(
        _ operation: (URL) async throws -> Result,
        validate: (URL, Result) throws -> Void
    ) async throws -> Result {
        let fileManager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(
            ".\(destination.lastPathComponent).export-ulysses-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        var published = false
        defer {
            if !published { try? fileManager.removeItem(at: staging) }
        }

        let result = try await operation(staging)
        try validate(staging, result)

        if fileManager.fileExists(atPath: destination.path) {
            let contents = try fileManager.contentsOfDirectory(atPath: destination.path)
                .filter { $0 != ".DS_Store" }
            guard contents.isEmpty else { throw ExportError.outputNotEmpty(destination.path) }
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: staging, to: destination)
        published = true
        return result
    }
}

struct OutputValidator {
    func validate(root: URL, summary: ExportSummary, snapshot: UlyssesLibrarySnapshot) throws {
        let fingerprint = snapshot.fingerprint
        guard summary.sheets == fingerprint.sheetPackages,
              summary.sheets == fingerprint.readableContentFiles
        else {
            throw ExportError.validationFailed(
                "Source packages (\(fingerprint.sheetPackages)), readable sheets (\(fingerprint.readableContentFiles)), and exported sheets (\(summary.sheets)) do not match."
            )
        }

        let expectedBundles = summary.sheets
            + summary.orderNotes
            + summary.metadataNotes
            + summary.reportNotes
            + (summary.favoriteSheets > 0 ? 1 : 0)
            + (!snapshot.filters.isEmpty ? 1 : 0)
        let bundles = try textBundles(in: root)
        guard bundles.count == expectedBundles else {
            throw ExportError.validationFailed("Expected \(expectedBundles) TextBundles but found \(bundles.count).")
        }

        var brokenAssets: [String] = []
        for bundle in bundles {
            let infoURL = bundle.appendingPathComponent("info.json")
            let textURL = bundle.appendingPathComponent("text.markdown")
            let assetsURL = bundle.appendingPathComponent("assets", isDirectory: true)
            guard FileManager.default.isReadableFile(atPath: infoURL.path),
                  FileManager.default.isReadableFile(atPath: textURL.path),
                  FileManager.default.fileExists(atPath: assetsURL.path)
            else {
                throw ExportError.validationFailed("Invalid TextBundle layout at \(bundle.path).")
            }
            let infoData = try Data(contentsOf: infoURL)
            guard let info = try JSONSerialization.jsonObject(with: infoData) as? [String: Any],
                  (info["version"] as? NSNumber)?.intValue == 2,
                  info["type"] as? String == "net.daringfireball.markdown"
            else {
                throw ExportError.validationFailed("Invalid TextBundle v2 info.json at \(infoURL.path).")
            }
            let markdown = try String(contentsOf: textURL, encoding: .utf8)
            for relativePath in assetPaths(in: markdown) {
                guard let decoded = relativePath.removingPercentEncoding else {
                    brokenAssets.append(relativePath)
                    continue
                }
                let target = bundle.appendingPathComponent(decoded).standardizedFileURL
                guard target.path.hasPrefix(assetsURL.standardizedFileURL.path + "/"),
                      FileManager.default.isReadableFile(atPath: target.path)
                else {
                    brokenAssets.append(relativePath)
                    continue
                }
            }
        }
        guard brokenAssets.isEmpty else {
            throw ExportError.validationFailed("Found \(brokenAssets.count) broken relative asset links. First: \(brokenAssets[0])")
        }

        let trashURL = root.appendingPathComponent("Trash", isDirectory: true)
        let trashBundles = try textBundles(in: trashURL).count
        guard trashBundles == summary.trashSheets else {
            throw ExportError.validationFailed("Expected \(summary.trashSheets) Ulysses Trash sheets in FSNotes Trash but found \(trashBundles).")
        }
    }

    private func textBundles(in root: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              )
        else { return [] }
        var bundles: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "textbundle" {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                bundles.append(url)
                enumerator.skipDescendants()
            }
        }
        return bundles
    }

    private func assetPaths(in markdown: String) -> [String] {
        let pattern = #"\((assets\/[^)]+)\)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(markdown.startIndex..., in: markdown)
        return expression.matches(in: markdown, range: range).compactMap { match in
            guard let swiftRange = Range(match.range(at: 1), in: markdown) else { return nil }
            return String(markdown[swiftRange])
        }
    }
}
