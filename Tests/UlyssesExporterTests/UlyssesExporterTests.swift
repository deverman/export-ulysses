import XCTest
@testable import UlyssesExporter

final class UlyssesExporterTests: XCTestCase {
    func testExportsSidebarNotesKeywordsAndFileAttachments() async throws {
        let root = try temporaryDirectory()
        let input = root.appendingPathComponent("Latest Backup.ulbackup")
        let sheet = input.appendingPathComponent("Ubiquitous Library.ulstoragebackup/Content/Unfiled-ulgroup/example.ulysses")
        let media = sheet.appendingPathComponent("Media")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try Data("image".utf8).write(to: media.appendingPathComponent("example.abc123.png"))
        try Data("sidebar image".utf8).write(to: media.appendingPathComponent("attachment.attach456.png"))
        try Data("file".utf8).write(to: media.appendingPathComponent("download.file123.pdf"))
        try contentXML("""
        <sheet>
        <string xml:space="preserve">
        <p><tags><tag kind="heading1"># </tag></tags>Main Title</p>
        <p>Body with <element kind="strong" startTag="**" endTag="**">bold</element>.</p>
        <p><element kind="image"><attribute identifier="image">abc123</attribute><attribute identifier="description">Alt text</attribute></element></p>
        </string>
        <attachment type="file">file123</attachment>
        <attachment type="file">attach456</attachment>
        <attachment type="keywords">alpha,beta value</attachment>
        <attachment type="note"><string xml:space="preserve"><p>Sidebar note text.</p></string></attachment>
        </sheet>
        """).write(to: sheet.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)

        let output = root.appendingPathComponent("Output")
        let summary = try await Exporter(maxConcurrentExports: 2).run(
            input: input.path,
            output: output.path,
            keepGroups: true,
            ignoring: []
        )

        XCTAssertEqual(summary.sheets, 1)
        XCTAssertEqual(summary.sidebarNotes, 1)
        XCTAssertEqual(summary.fileAttachments, 2)
        XCTAssertEqual(summary.inlineImages, 1)
        XCTAssertEqual(summary.keywords, 2)
        XCTAssertEqual(summary.materialSheets, 0)
        XCTAssertEqual(summary.missingMedia, 0)
        XCTAssertEqual(summary.recoveredMedia, 0)

        let bundle = output.appendingPathComponent("Inbox/Main Title.textbundle")
        let markdown = try String(contentsOf: bundle.appendingPathComponent("text.markdown"), encoding: .utf8)
        XCTAssertTrue(markdown.contains("# Main Title"))
        XCTAssertTrue(markdown.contains("Body with **bold**."))
        XCTAssertTrue(markdown.contains("![Alt text](assets/example.abc123.png)"))
        XCTAssertTrue(markdown.contains("## Ulysses Attachments"))
        XCTAssertTrue(markdown.contains("![attachment.attach456.png](assets/attachment.attach456.png)"))
        XCTAssertTrue(markdown.contains("[download.file123.pdf](assets/download.file123.pdf)"))
        XCTAssertTrue(markdown.contains("## Ulysses Sidebar Notes"))
        XCTAssertTrue(markdown.contains("Sidebar note text."))
        XCTAssertTrue(markdown.contains("#alpha #beta-value"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("assets/example.abc123.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("assets/attachment.attach456.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("assets/download.file123.pdf").path))
    }

    func testPreservesProjectArchivePathAndMaterialTag() async throws {
        let root = try temporaryDirectory()
        let input = root.appendingPathComponent("Backup.ulbackup")
        let projectContent = input.appendingPathComponent("archive.ulstoragebackup/Content")
        let main = projectContent.appendingPathComponent("Main-ulgroup")
        let sheet = main.appendingPathComponent("material.ulysses")
        try FileManager.default.createDirectory(at: sheet, withIntermediateDirectories: true)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict>
          <key>displayName</key>
          <string>Archive</string>
        </dict>
        </plist>
        """.write(to: projectContent.appendingPathComponent("Info.ulgroup"), atomically: true, encoding: .utf8)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict>
          <key>displayName</key>
          <string>Content</string>
        </dict>
        </plist>
        """.write(to: main.appendingPathComponent("Info.ulgroup"), atomically: true, encoding: .utf8)
        try contentXML("""
        <sheet>
        <string xml:space="preserve">
        <p><tags><tag kind="heading1"># </tag></tags>Archived Material</p>
        </string>
        <setting name="material" value="YES"></setting>
        </sheet>
        """).write(to: sheet.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)

        let output = root.appendingPathComponent("Output")
        let summary = try await Exporter().run(input: input.path, output: output.path, keepGroups: true, ignoring: [])

        XCTAssertEqual(summary.sheets, 1)
        XCTAssertEqual(summary.materialSheets, 1)
        let bundle = output.appendingPathComponent("Archive/Content/Archived Material.textbundle")
        let markdown = try String(contentsOf: bundle.appendingPathComponent("text.markdown"), encoding: .utf8)
        XCTAssertTrue(markdown.contains("## Ulysses Migration Tags"))
        XCTAssertTrue(markdown.contains("#ulysses/material #ulysses/archive"))
    }

    func testWritesUlyssesSheetOrderNotesAndTagsGluedSheets() async throws {
        let root = try temporaryDirectory()
        let input = root.appendingPathComponent("Backup.ulbackup")
        let projectContent = input.appendingPathComponent("project.ulstoragebackup/Content")
        let main = projectContent.appendingPathComponent("Main-ulgroup")
        let orderedGroup = main.appendingPathComponent("ordered-ulgroup")
        let first = orderedGroup.appendingPathComponent("first.ulysses")
        let second = orderedGroup.appendingPathComponent("second.ulysses")
        let third = orderedGroup.appendingPathComponent("third.ulysses")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: third, withIntermediateDirectories: true)
        try writeInfo(displayName: "Project", to: projectContent.appendingPathComponent("Info.ulgroup"))
        try writeInfo(displayName: "Content", to: main.appendingPathComponent("Info.ulgroup"))
        try writeInfo(
            displayName: "Ordered",
            sheetClusters: [["second.ulysses"], ["first.ulysses", "third.ulysses"]],
            to: orderedGroup.appendingPathComponent("Info.ulgroup")
        )
        try titledSheet("First").write(to: first.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)
        try titledSheet("Second").write(to: second.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)
        try titledSheet("Third").write(to: third.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)

        let output = root.appendingPathComponent("Output")
        let summary = try await Exporter(maxConcurrentExports: 3).run(input: input.path, output: output.path, keepGroups: true, ignoring: [])

        XCTAssertEqual(summary.sheets, 3)
        XCTAssertEqual(summary.gluedSheets, 2)
        XCTAssertEqual(summary.orderNotes, 1)

        let folder = output.appendingPathComponent("Project/Content/Ordered")
        let orderMarkdown = try String(
            contentsOf: folder.appendingPathComponent("Ulysses Sheet Order.textbundle/text.markdown"),
            encoding: .utf8
        )
        XCTAssertTrue(orderMarkdown.contains("#ulysses/order-index #ulysses/glued"))
        XCTAssertTrue(orderMarkdown.contains("1. [Second](Second.textbundle)"))
        XCTAssertTrue(orderMarkdown.contains("2. Glued sheets"))
        XCTAssertTrue(orderMarkdown.contains("- [First](First.textbundle)"))
        XCTAssertTrue(orderMarkdown.contains("- [Third](Third.textbundle)"))
        XCTAssertLessThan(orderMarkdown.range(of: "[Second]")!.lowerBound, orderMarkdown.range(of: "Glued sheets")!.lowerBound)

        let firstMarkdown = try String(contentsOf: folder.appendingPathComponent("First.textbundle/text.markdown"), encoding: .utf8)
        let thirdMarkdown = try String(contentsOf: folder.appendingPathComponent("Third.textbundle/text.markdown"), encoding: .utf8)
        let secondMarkdown = try String(contentsOf: folder.appendingPathComponent("Second.textbundle/text.markdown"), encoding: .utf8)
        XCTAssertTrue(firstMarkdown.contains("#ulysses/glued"))
        XCTAssertTrue(thirdMarkdown.contains("#ulysses/glued"))
        XCTAssertFalse(secondMarkdown.contains("#ulysses/glued"))
    }

    func testRecoversMissingSheetMediaFromSameBackup() async throws {
        let root = try temporaryDirectory()
        let input = root.appendingPathComponent("Backup.ulbackup")
        let sourceSheet = input.appendingPathComponent("Store.ulstoragebackup/Content/Unfiled-ulgroup/source.ulysses")
        let referencingSheet = input.appendingPathComponent("Store.ulstoragebackup/Content/Unfiled-ulgroup/reference.ulysses")
        try FileManager.default.createDirectory(at: sourceSheet.appendingPathComponent("Media"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: referencingSheet, withIntermediateDirectories: true)
        try Data("recovered".utf8).write(to: sourceSheet.appendingPathComponent("Media/Screen Shot.recover123.png"))
        try contentXML("""
        <sheet>
        <string xml:space="preserve"><p>Media Source</p></string>
        </sheet>
        """).write(to: sourceSheet.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)
        try contentXML("""
        <sheet>
        <string xml:space="preserve">
        <p><tags><tag kind="heading1"># </tag></tags>Recovered Reference</p>
        </string>
        <attachment type="file">recover123</attachment>
        </sheet>
        """).write(to: referencingSheet.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)

        let output = root.appendingPathComponent("Output")
        let summary = try await Exporter().run(input: input.path, output: output.path, keepGroups: false, ignoring: [])

        XCTAssertEqual(summary.sheets, 2)
        XCTAssertEqual(summary.missingMedia, 0)
        XCTAssertEqual(summary.recoveredMedia, 1)
        let bundle = output.appendingPathComponent("Recovered Reference.textbundle")
        let markdown = try String(contentsOf: bundle.appendingPathComponent("text.markdown"), encoding: .utf8)
        XCTAssertTrue(markdown.contains("![Screen Shot.recover123.png](assets/Screen%20Shot.recover123.png)"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("assets/Screen Shot.recover123.png").path))
    }

    func testReportsMissingMediaWithoutDroppingReferences() async throws {
        let root = try temporaryDirectory()
        let input = root.appendingPathComponent("Backup.ulbackup")
        let sheet = input.appendingPathComponent("Store.ulstoragebackup/Content/Unfiled-ulgroup/missing.ulysses")
        try FileManager.default.createDirectory(at: sheet, withIntermediateDirectories: true)
        try contentXML("""
        <sheet>
        <string xml:space="preserve">
        <p><tags><tag kind="heading1"># </tag></tags>Missing Media</p>
        <p><element kind="image"><attribute identifier="image">not-found</attribute></element></p>
        </string>
        </sheet>
        """).write(to: sheet.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)

        let output = root.appendingPathComponent("Output")
        let summary = try await Exporter().run(input: input.path, output: output.path, keepGroups: false, ignoring: [])

        XCTAssertEqual(summary.sheets, 1)
        XCTAssertEqual(summary.inlineImages, 1)
        XCTAssertEqual(summary.missingMedia, 1)
        let markdown = try String(contentsOf: output.appendingPathComponent("Missing Media.textbundle/text.markdown"), encoding: .utf8)
        XCTAssertTrue(markdown.contains("![]()"))
    }

    private func contentXML(_ body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        \(body)
        """
    }

    private func titledSheet(_ title: String) -> String {
        contentXML("""
        <sheet>
        <string xml:space="preserve">
        <p><tags><tag kind="heading1"># </tag></tags>\(title)</p>
        </string>
        </sheet>
        """)
    }

    private func writeInfo(displayName: String, sheetClusters: [[String]] = [], to url: URL) throws {
        let clusters = sheetClusters.map { cluster in
            let sheets = cluster.map { "<string>\($0)</string>" }.joined(separator: "\n")
            return "<array>\n\(sheets)\n</array>"
        }.joined(separator: "\n")
        let sheetClustersXML = sheetClusters.isEmpty ? "" : """

          <key>sheetClusters</key>
          <array>
          \(clusters)
          </array>
        """
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict>
          <key>displayName</key>
          <string>\(displayName)</string>\(sheetClustersXML)
        </dict>
        </plist>
        """.write(to: url, atomically: true, encoding: .utf8)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-ulysses-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
