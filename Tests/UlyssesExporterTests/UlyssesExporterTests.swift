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
            allowUnknownFormat: true
        )

        XCTAssertEqual(summary.sheets, 1)
        XCTAssertEqual(summary.sidebarNotes, 1)
        XCTAssertEqual(summary.fileAttachments, 2)
        XCTAssertEqual(summary.inlineImages, 1)
        XCTAssertEqual(summary.keywords, 2)
        XCTAssertEqual(summary.materialSheets, 0)
        XCTAssertEqual(summary.missingMedia, 0)
        XCTAssertEqual(summary.recoveredMedia, 0)

        let bundle = output.appendingPathComponent("Main Title.textbundle")
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
        let summary = try await Exporter().run(input: input.path, output: output.path, allowUnknownFormat: true)

        XCTAssertEqual(summary.sheets, 1)
        XCTAssertEqual(summary.materialSheets, 1)
        let bundle = output.appendingPathComponent("Archive (Ulysses)/Content/Archived Material.textbundle")
        let markdown = try String(contentsOf: bundle.appendingPathComponent("text.markdown"), encoding: .utf8)
        XCTAssertTrue(markdown.contains("## Ulysses Migration Tags"))
        XCTAssertTrue(markdown.contains("#ulysses/material #ulysses/archive"))
    }

    func testOrdinaryArchiveNamedGroupIsNotTaggedAsUlyssesArchive() async throws {
        let root = try temporaryDirectory()
        let input = root.appendingPathComponent("Backup.ulbackup")
        let group = input.appendingPathComponent("Ubiquitous Library.ulstoragebackup/Content/Groups-ulgroup/archive-ulgroup")
        let sheet = group.appendingPathComponent("note.ulysses")
        try FileManager.default.createDirectory(at: sheet, withIntermediateDirectories: true)
        try writeInfo(displayName: "Archive", to: group.appendingPathComponent("Info.ulgroup"))
        try titledSheet("Regular Group Note").write(to: sheet.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)

        let output = root.appendingPathComponent("Output")
        let summary = try await Exporter().run(input: input.path, output: output.path, allowUnknownFormat: true)
        let markdown = try String(
            contentsOf: output.appendingPathComponent("Archive/Regular Group Note.textbundle/text.markdown"),
            encoding: .utf8
        )

        XCTAssertEqual(summary.archiveSheets, 0)
        XCTAssertFalse(markdown.contains("#ulysses/archive"))
    }

    func testOrdinaryInboxAndTrashGroupsDoNotBecomeFSNotesSystemLocations() async throws {
        let root = try temporaryDirectory()
        let input = root.appendingPathComponent("Backup.ulbackup")
        let groups = input.appendingPathComponent("Ubiquitous Library.ulstoragebackup/Content/Groups-ulgroup")
        let inboxGroup = groups.appendingPathComponent("ordinary-inbox-ulgroup")
        let trashGroup = groups.appendingPathComponent("ordinary-trash-ulgroup")
        let inboxSheet = inboxGroup.appendingPathComponent("inbox-note.ulysses")
        let trashSheet = trashGroup.appendingPathComponent("trash-note.ulysses")
        try FileManager.default.createDirectory(at: inboxSheet, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trashSheet, withIntermediateDirectories: true)
        try writeInfo(displayName: "Inbox", to: inboxGroup.appendingPathComponent("Info.ulgroup"))
        try writeInfo(displayName: "Trash", to: trashGroup.appendingPathComponent("Info.ulgroup"))
        try titledSheet("Ordinary Inbox Note").write(to: inboxSheet.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)
        try titledSheet("Ordinary Trash Note").write(to: trashSheet.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)

        let output = root.appendingPathComponent("Output")
        let summary = try await Exporter().run(input: input.path, output: output.path, allowUnknownFormat: true)

        XCTAssertEqual(summary.trashSheets, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("Inbox (Ulysses Group)/Ordinary Inbox Note.textbundle").path))
        let markdown = try String(
            contentsOf: output.appendingPathComponent("Trash (Ulysses Group)/Ordinary Trash Note.textbundle/text.markdown"),
            encoding: .utf8
        )
        XCTAssertFalse(markdown.contains("#ulysses/trash"))
    }

    func testNestedUlyssesTrashIsFlattenedIntoFSNotesTrashWithSourceOrderPreserved() async throws {
        let root = try temporaryDirectory()
        let input = root.appendingPathComponent("Backup.ulbackup")
        let group = input.appendingPathComponent("Ubiquitous Library.ulstoragebackup/Content/Trash-ultrash/deleted-project-ulgroup")
        let first = group.appendingPathComponent("first.ulysses")
        let second = group.appendingPathComponent("second.ulysses")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try writeInfo(
            displayName: "Deleted Project",
            sheetClusters: [["second.ulysses"], ["first.ulysses"]],
            to: group.appendingPathComponent("Info.ulgroup")
        )
        try titledSheet("First Deleted Note").write(to: first.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)
        try titledSheet("Second Deleted Note").write(to: second.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)

        let output = root.appendingPathComponent("Output")
        let summary = try await Exporter().run(input: input.path, output: output.path, allowUnknownFormat: true)

        XCTAssertEqual(summary.trashSheets, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("Trash/First Deleted Note.textbundle").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("Trash/Second Deleted Note.textbundle").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("Trash/Deleted Project").path))
        let map = try String(
            contentsOf: output.appendingPathComponent("_Ulysses Migration/Ulysses Library Map.textbundle/text.markdown"),
            encoding: .utf8
        )
        XCTAssertTrue(map.contains("Ulysses Sheet Order: Trash (Ulysses source: Trash / Deleted Project)"))
        XCTAssertLessThan(map.range(of: "[Second Deleted Note]")!.lowerBound, map.range(of: "[First Deleted Note]")!.lowerBound)
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
        let summary = try await Exporter(maxConcurrentExports: 3).run(input: input.path, output: output.path, allowUnknownFormat: true)

        XCTAssertEqual(summary.sheets, 3)
        XCTAssertEqual(summary.gluedSheets, 2)
        XCTAssertEqual(summary.orderNotes, 1)

        let folder = output.appendingPathComponent("Project/Content/Ordered")
        let orderMarkdown = try String(
            contentsOf: output.appendingPathComponent("_Ulysses Migration/Ulysses Library Map.textbundle/text.markdown"),
            encoding: .utf8
        )
        XCTAssertTrue(orderMarkdown.contains("## Ulysses Sheet Order: Project / Content / Ordered"))
        XCTAssertTrue(orderMarkdown.contains("#ulysses/order-index"))
        XCTAssertTrue(orderMarkdown.contains("#ulysses/glued"))
        XCTAssertTrue(orderMarkdown.contains("1. [Second](fsnotes://find?id=Second) (`Second.textbundle`)"))
        XCTAssertTrue(orderMarkdown.contains("2. Glued sheets"))
        XCTAssertTrue(orderMarkdown.contains("- [First](fsnotes://find?id=First) (`First.textbundle`)"))
        XCTAssertTrue(orderMarkdown.contains("- [Third](fsnotes://find?id=Third) (`Third.textbundle`)"))
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
        let summary = try await Exporter().run(input: input.path, output: output.path, allowUnknownFormat: true)

        XCTAssertEqual(summary.sheets, 2)
        XCTAssertEqual(summary.missingMedia, 0)
        XCTAssertEqual(summary.recoveredMedia, 1)
        let bundle = output.appendingPathComponent("Inbox (Ulysses Group)/Recovered Reference.textbundle")
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
        let summary = try await Exporter().run(input: input.path, output: output.path, allowUnknownFormat: true)

        XCTAssertEqual(summary.sheets, 1)
        XCTAssertEqual(summary.inlineImages, 1)
        XCTAssertEqual(summary.missingMedia, 1)
        let markdown = try String(contentsOf: output.appendingPathComponent("Inbox (Ulysses Group)/Missing Media.textbundle/text.markdown"), encoding: .utf8)
        XCTAssertTrue(markdown.contains("![]()"))
    }

    func testWritesReportMetadataNotesAndFSNotesInfoJSON() async throws {
        let root = try temporaryDirectory()
        let input = root.appendingPathComponent("Backup.ulbackup")
        let projectContent = input.appendingPathComponent("archive.ulstoragebackup/Content")
        let main = projectContent.appendingPathComponent("Main-ulgroup")
        let templates = main.appendingPathComponent("templates-ulgroup")
        let templateSheet = templates.appendingPathComponent("template.ulysses")
        let trashSheet = input.appendingPathComponent("Ubiquitous Library.ulstoragebackup/Content/Trash-ultrash/trash.ulysses")
        try FileManager.default.createDirectory(at: templateSheet, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trashSheet, withIntermediateDirectories: true)
        try writeInfo(displayName: "Archive", to: projectContent.appendingPathComponent("Info.ulgroup"))
        try writeInfo(displayName: "Content", to: main.appendingPathComponent("Info.ulgroup"))
        try writeInfo(
            displayName: "Templates",
            sheetClusters: [["template.ulysses"]],
            childOrder: ["template.ulysses"],
            icon: "Material",
            tint: "gray",
            countingGoal: ["counterIdentifier": "words", "targetResult": "100", "type": "daily"],
            to: templates.appendingPathComponent("Info.ulgroup")
        )
        try contentXML("""
        <sheet>
        <string xml:space="preserve">
        <p><tags><tag kind="heading1"># </tag></tags>Reusable Draft</p>
        </string>
        <setting name="favorite" value="YES"></setting>
        </sheet>
        """).write(to: templateSheet.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)
        try titledSheet("Deleted Draft").write(to: trashSheet.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)

        let output = root.appendingPathComponent("Output")
        let summary = try await Exporter().run(input: input.path, output: output.path, allowUnknownFormat: true)

        XCTAssertEqual(summary.sheets, 2)
        XCTAssertEqual(summary.archiveSheets, 1)
        XCTAssertEqual(summary.templateSheets, 1)
        XCTAssertEqual(summary.trashSheets, 1)
        XCTAssertEqual(summary.favoriteSheets, 1)
        XCTAssertEqual(summary.reportNotes, 1)
        XCTAssertEqual(summary.metadataNotes, 1)

        let templateMarkdown = try String(
            contentsOf: output.appendingPathComponent("Archive (Ulysses)/Content/Templates/Reusable Draft.textbundle/text.markdown"),
            encoding: .utf8
        )
        XCTAssertTrue(templateMarkdown.contains("#ulysses/favorite"))
        XCTAssertTrue(templateMarkdown.contains("#ulysses/archive"))
        XCTAssertTrue(templateMarkdown.contains("#ulysses/template"))

        let trashMarkdown = try String(
            contentsOf: output.appendingPathComponent("Trash/Deleted Draft.textbundle/text.markdown"),
            encoding: .utf8
        )
        XCTAssertTrue(trashMarkdown.contains("#ulysses/trash"))

        let metadataMarkdown = try String(
            contentsOf: output.appendingPathComponent("_Ulysses Migration/Ulysses Group Metadata.textbundle/text.markdown"),
            encoding: .utf8
        )
        XCTAssertTrue(metadataMarkdown.contains("## Ulysses Metadata: Archive (Ulysses) / Content / Templates"))
        XCTAssertTrue(metadataMarkdown.contains("#ulysses/group-metadata"))
        XCTAssertTrue(metadataMarkdown.contains("#ulysses/template"))
        XCTAssertTrue(metadataMarkdown.contains("- Ulysses icon: Material"))
        XCTAssertTrue(metadataMarkdown.contains("- Ulysses color: gray"))
        XCTAssertTrue(metadataMarkdown.contains("### Goal"))
        XCTAssertTrue(metadataMarkdown.contains("- targetResult: 100"))

        let reportMarkdown = try String(contentsOf: output.appendingPathComponent("_Ulysses Migration/Ulysses Export Report.textbundle/text.markdown"), encoding: .utf8)
        XCTAssertTrue(reportMarkdown.contains("- Sheets: 2"))
        XCTAssertTrue(reportMarkdown.contains("- Template sheets: 1"))
        XCTAssertTrue(reportMarkdown.contains("- Trash sheets: 1"))
        XCTAssertTrue(reportMarkdown.contains("## Finish In FSNotes"))
        XCTAssertTrue(reportMarkdown.contains("FSNotes Empty Trash permanently deletes"))

        let reportData = try Data(contentsOf: output.appendingPathComponent(".export-ulysses/ulysses-export-report.json"))
        let report = try JSONSerialization.jsonObject(with: reportData) as? [String: Any]
        let counts = try XCTUnwrap(report?["counts"] as? [String: Any])
        XCTAssertEqual(counts["sheets"] as? Int, 2)
        XCTAssertEqual(counts["favoriteSheets"] as? Int, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent(".export-ulysses/manifest.json").path))

        let infoData = try Data(contentsOf: output.appendingPathComponent("Archive (Ulysses)/Content/Templates/Reusable Draft.textbundle/info.json"))
        let info = try JSONSerialization.jsonObject(with: infoData) as? [String: Any]
        XCTAssertEqual(info?["version"] as? Int, 2)
        XCTAssertEqual(info?["type"] as? String, "net.daringfireball.markdown")
        XCTAssertEqual(info?["flatExtension"] as? String, "markdown")
        XCTAssertEqual(info?["creatorIdentifier"] as? String, "org.deverman.export-ulysses")
        XCTAssertNotNil(info?["created"])
        XCTAssertNotNil(info?["modified"])
    }

    func testReadsFavoritesPlistAndSavedFilters() async throws {
        let root = try temporaryDirectory()
        let input = root.appendingPathComponent("Backup.ulbackup")
        let content = input.appendingPathComponent("Ubiquitous Library.ulstoragebackup/Content")
        let inbox = content.appendingPathComponent("Unfiled-ulgroup")
        let sheet = inbox.appendingPathComponent("favorite.ulysses")
        let trashedSheet = content.appendingPathComponent("Trash-ultrash/trashed-favorite.ulysses")
        let filter = content.appendingPathComponent("published-ulfilter")
        try FileManager.default.createDirectory(at: sheet, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trashedSheet, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: filter, withIntermediateDirectories: true)
        try titledSheet("Favorite Sheet").write(to: sheet.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)
        try titledSheet("Trashed Favorite").write(to: trashedSheet.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)

        let favoritesData = try PropertyListSerialization.data(
            fromPropertyList: [
                "order": [
                    "Unfiled-ulgroup/favorite.ulysses",
                    "Trash-ultrash/trashed-favorite.ulysses"
                ]
            ],
            format: .binary,
            options: 0
        )
        try favoritesData.write(to: content.appendingPathComponent("favorites"))
        let filterData = try PropertyListSerialization.data(
            fromPropertyList: [
                "displayName": "Published Articles",
                "query": ["conditions": [["conditionType": "KeywordSearch", "keywords": ["published"]]]]
            ],
            format: .xml,
            options: 0
        )
        try filterData.write(to: filter.appendingPathComponent("Info.ulfilter"))

        let output = root.appendingPathComponent("Output")
        let summary = try await Exporter().run(input: input.path, output: output.path, allowUnknownFormat: true)

        XCTAssertEqual(summary.favoriteSheets, 1)
        XCTAssertEqual(summary.savedFilters, 1)
        let sheetMarkdown = try String(contentsOf: output.appendingPathComponent("Favorite Sheet.textbundle/text.markdown"), encoding: .utf8)
        XCTAssertTrue(sheetMarkdown.contains("#ulysses/favorite"))
        let trashedMarkdown = try String(contentsOf: output.appendingPathComponent("Trash/Trashed Favorite.textbundle/text.markdown"), encoding: .utf8)
        XCTAssertFalse(trashedMarkdown.contains("#ulysses/favorite"))
        let favorites = try String(contentsOf: output.appendingPathComponent("_Ulysses Migration/Ulysses Favorites.textbundle/text.markdown"), encoding: .utf8)
        XCTAssertTrue(favorites.contains("[Favorite Sheet](fsnotes://find?id=Favorite%20Sheet)"))
        XCTAssertFalse(favorites.contains("Trashed Favorite"))
        let filters = try String(contentsOf: output.appendingPathComponent("_Ulysses Migration/Ulysses Saved Filters.textbundle/text.markdown"), encoding: .utf8)
        XCTAssertTrue(filters.contains("## Published Articles"))
        XCTAssertTrue(filters.contains("KeywordSearch"))
    }

    func testRendersFootnotesCommentsAnnotationsAndCodeBlocks() async throws {
        let root = try temporaryDirectory()
        let input = root.appendingPathComponent("Backup.ulbackup")
        let sheet = input.appendingPathComponent("Store.ulstoragebackup/Content/Unfiled-ulgroup/markup.ulysses")
        try FileManager.default.createDirectory(at: sheet, withIntermediateDirectories: true)
        try contentXML("""
        <sheet>
        <string xml:space="preserve">
        <p><tags><tag kind="heading1"># </tag></tags>Markup</p>
        <p>Body<element kind="footnote"><attribute identifier="text"><string xml:space="preserve"><p>Footnote text.</p></string></attribute></element></p>
        <p>Review <element kind="inlineComment">this claim</element>.</p>
        <p><element kind="annotation"><attribute identifier="text"><string xml:space="preserve"><p>Check source</p></string></attribute>annotated words</element></p>
        <p><tags><tag kind="comment">%% </tag></tags>Block comment</p>
        <p><tags><tag kind="codeblock">''</tag></tags>let value = 1</p>
        </string>
        </sheet>
        """).write(to: sheet.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)

        let output = root.appendingPathComponent("Output")
        _ = try await Exporter().run(input: input.path, output: output.path, allowUnknownFormat: true)
        let markdown = try String(contentsOf: output.appendingPathComponent("Inbox (Ulysses Group)/Markup.textbundle/text.markdown"), encoding: .utf8)

        XCTAssertTrue(markdown.contains("Body[^ulysses-1]"))
        XCTAssertTrue(markdown.contains("[^ulysses-1]: Footnote text."))
        XCTAssertTrue(markdown.contains("**[Ulysses comment: this claim]**"))
        XCTAssertTrue(markdown.contains("annotated words **[Ulysses annotation: Check source]**"))
        XCTAssertTrue(markdown.contains("> **Ulysses comment:** Block comment"))
        XCTAssertTrue(markdown.contains("```\nlet value = 1\n```"))
    }

    func testMigrationAlwaysIncludesEveryGroup() async throws {
        let root = try temporaryDirectory()
        let input = root.appendingPathComponent("Backup.ulbackup")
        let groups = input.appendingPathComponent("Store.ulstoragebackup/Content/Groups-ulgroup")
        let ignored = groups.appendingPathComponent("ignored-ulgroup")
        let kept = groups.appendingPathComponent("kept-ulgroup")
        try FileManager.default.createDirectory(at: ignored.appendingPathComponent("ignored.ulysses"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: kept.appendingPathComponent("kept.ulysses"), withIntermediateDirectories: true)
        try writeInfo(displayName: "Ignored", to: ignored.appendingPathComponent("Info.ulgroup"))
        try writeInfo(displayName: "Kept", to: kept.appendingPathComponent("Info.ulgroup"))
        try titledSheet("Ignored Note").write(to: ignored.appendingPathComponent("ignored.ulysses/Content.xml"), atomically: true, encoding: .utf8)
        try titledSheet("Kept Note").write(to: kept.appendingPathComponent("kept.ulysses/Content.xml"), atomically: true, encoding: .utf8)

        let output = root.appendingPathComponent("Output")
        let summary = try await Exporter().run(input: input.path, output: output.path, allowUnknownFormat: true)

        XCTAssertEqual(summary.sheets, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("Kept/Kept Note.textbundle").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("Ignored/Ignored Note.textbundle").path))
    }

    func testRefusesToAppendASecondMigrationToNonEmptyOutput() async throws {
        let root = try temporaryDirectory()
        let input = root.appendingPathComponent("Backup.ulbackup")
        let sheet = input.appendingPathComponent("Store.ulstoragebackup/Content/Unfiled-ulgroup/note.ulysses")
        try FileManager.default.createDirectory(at: sheet, withIntermediateDirectories: true)
        try titledSheet("One Note").write(to: sheet.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)
        let output = root.appendingPathComponent("Output")
        _ = try await Exporter().run(input: input.path, output: output.path, allowUnknownFormat: true)

        do {
            _ = try await Exporter().run(input: input.path, output: output.path, allowUnknownFormat: true)
            XCTFail("Expected a non-empty output error")
        } catch let error as ExportError {
            guard case .outputNotEmpty = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testDuplicateTitlesUseDistinctFSNotesTargets() async throws {
        let root = try temporaryDirectory()
        let input = root.appendingPathComponent("Backup.ulbackup")
        let group = input.appendingPathComponent("Store.ulstoragebackup/Content/Groups-ulgroup/duplicates-ulgroup")
        let first = group.appendingPathComponent("first.ulysses")
        let second = group.appendingPathComponent("second.ulysses")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try writeInfo(displayName: "Duplicates", sheetClusters: [["first.ulysses"], ["second.ulysses"]], to: group.appendingPathComponent("Info.ulgroup"))
        try titledSheet("Same Title").write(to: first.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)
        try titledSheet("Same Title").write(to: second.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)

        let output = root.appendingPathComponent("Output")
        _ = try await Exporter(maxConcurrentExports: 2).run(input: input.path, output: output.path, allowUnknownFormat: true)
        let map = try String(contentsOf: output.appendingPathComponent("_Ulysses Migration/Ulysses Library Map.textbundle/text.markdown"), encoding: .utf8)

        XCTAssertTrue(map.contains("fsnotes://find?id=Same%20Title)"))
        XCTAssertTrue(map.contains("fsnotes://find?id=Same%20Title%20%281%29)"))
    }

    func testFSNotesTargetsAreUniqueAcrossFoldersIgnoringCase() async throws {
        let root = try temporaryDirectory()
        let input = root.appendingPathComponent("Backup.ulbackup")
        let groups = input.appendingPathComponent("Store.ulstoragebackup/Content/Groups-ulgroup")
        let firstGroup = groups.appendingPathComponent("first-ulgroup")
        let secondGroup = groups.appendingPathComponent("second-ulgroup")
        let first = firstGroup.appendingPathComponent("first.ulysses")
        let second = secondGroup.appendingPathComponent("second.ulysses")
        let firstSibling = firstGroup.appendingPathComponent("first-sibling.ulysses")
        let secondSibling = secondGroup.appendingPathComponent("second-sibling.ulysses")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: firstSibling, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondSibling, withIntermediateDirectories: true)
        try writeInfo(
            displayName: "First",
            sheetClusters: [["first.ulysses"], ["first-sibling.ulysses"]],
            to: firstGroup.appendingPathComponent("Info.ulgroup")
        )
        try writeInfo(
            displayName: "Second",
            sheetClusters: [["second.ulysses"], ["second-sibling.ulysses"]],
            to: secondGroup.appendingPathComponent("Info.ulgroup")
        )
        let sharedName = String(repeating: "A", count: 180)
        let caseVariant = sharedName.lowercased()
        let suffixedName = String(caseVariant.prefix(176)) + " (1)"
        try titledSheet(sharedName).write(to: first.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)
        try titledSheet(caseVariant).write(to: second.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)
        try titledSheet("First Sibling").write(to: firstSibling.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)
        try titledSheet("Second Sibling").write(to: secondSibling.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)

        let output = root.appendingPathComponent("Output")
        let summary = try await Exporter(maxConcurrentExports: 2).run(
            input: input.path,
            output: output.path,
            allowUnknownFormat: true
        )
        let map = try String(
            contentsOf: output.appendingPathComponent("_Ulysses Migration/Ulysses Library Map.textbundle/text.markdown"),
            encoding: .utf8
        )

        XCTAssertEqual(summary.duplicateTitles, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("First/\(sharedName).textbundle").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("Second/\(suffixedName).textbundle").path))
        XCTAssertTrue(map.contains("fsnotes://find?id=\(sharedName)"))
        XCTAssertTrue(map.contains("fsnotes://find?id=\(String(caseVariant.prefix(176)))%20%281%29)"))
    }

    func testDuplicateAllocationPreservesNaturalSuffixedTitleAndMatchesAnalysis() async throws {
        let root = try temporaryDirectory()
        let input = root.appendingPathComponent("Backup.ulbackup")
        let group = input.appendingPathComponent("Store.ulstoragebackup/Content/Groups-ulgroup/duplicates-ulgroup")
        let sheets = ["first.ulysses", "second.ulysses", "natural.ulysses"]
        for name in sheets {
            try FileManager.default.createDirectory(at: group.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try writeInfo(
            displayName: "Duplicates",
            sheetClusters: sheets.map { [$0] },
            to: group.appendingPathComponent("Info.ulgroup")
        )
        try titledSheet("Same Title").write(to: group.appendingPathComponent("first.ulysses/Content.xml"), atomically: true, encoding: .utf8)
        try titledSheet("Same Title").write(to: group.appendingPathComponent("second.ulysses/Content.xml"), atomically: true, encoding: .utf8)
        try titledSheet("Same Title (1)").write(to: group.appendingPathComponent("natural.ulysses/Content.xml"), atomically: true, encoding: .utf8)

        let analysis = try await Exporter(maxConcurrentExports: 3).analyze(
            input: input.path,
            allowUnknownFormat: true
        )
        let output = root.appendingPathComponent("Output")
        let summary = try await Exporter(maxConcurrentExports: 3).run(
            input: input.path,
            output: output.path,
            allowUnknownFormat: true
        )

        XCTAssertEqual(analysis.summary.duplicateTitles, 1)
        XCTAssertEqual(summary.duplicateTitles, analysis.summary.duplicateTitles)
        let folder = output.appendingPathComponent("Duplicates")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Same Title.textbundle").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Same Title (1).textbundle").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Same Title (2).textbundle").path))
    }

    func testCollidingGroupNamesRemainSeparate() async throws {
        let root = try temporaryDirectory()
        let input = root.appendingPathComponent("Backup.ulbackup")
        let groups = input.appendingPathComponent("Store.ulstoragebackup/Content/Groups-ulgroup")
        let firstGroup = groups.appendingPathComponent("one-ulgroup")
        let secondGroup = groups.appendingPathComponent("two-ulgroup")
        try FileManager.default.createDirectory(at: firstGroup.appendingPathComponent("first.ulysses"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondGroup.appendingPathComponent("second.ulysses"), withIntermediateDirectories: true)
        try writeInfo(displayName: "Same Group", to: firstGroup.appendingPathComponent("Info.ulgroup"))
        try writeInfo(displayName: "Same Group", to: secondGroup.appendingPathComponent("Info.ulgroup"))
        try titledSheet("First Note").write(to: firstGroup.appendingPathComponent("first.ulysses/Content.xml"), atomically: true, encoding: .utf8)
        try titledSheet("Second Note").write(to: secondGroup.appendingPathComponent("second.ulysses/Content.xml"), atomically: true, encoding: .utf8)

        let output = root.appendingPathComponent("Output")
        _ = try await Exporter().run(input: input.path, output: output.path, allowUnknownFormat: true)

        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("Same Group [one]/First Note.textbundle").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("Same Group [two]/Second Note.textbundle").path))
    }

    func testCollidingParentGroupsDoNotMergeDistinctChildren() async throws {
        let root = try temporaryDirectory()
        let input = root.appendingPathComponent("Backup.ulbackup")
        let groups = input.appendingPathComponent("Store.ulstoragebackup/Content/Groups-ulgroup")
        let firstParent = groups.appendingPathComponent("one-ulgroup")
        let secondParent = groups.appendingPathComponent("two-ulgroup")
        let firstChild = firstParent.appendingPathComponent("alpha-ulgroup")
        let secondChild = secondParent.appendingPathComponent("beta-ulgroup")
        try FileManager.default.createDirectory(at: firstChild.appendingPathComponent("first.ulysses"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondChild.appendingPathComponent("second.ulysses"), withIntermediateDirectories: true)
        try writeInfo(displayName: "Store", to: groups.deletingLastPathComponent().appendingPathComponent("Info.ulgroup"))
        try writeInfo(displayName: "Same Parent", to: firstParent.appendingPathComponent("Info.ulgroup"))
        try writeInfo(displayName: "Same Parent", to: secondParent.appendingPathComponent("Info.ulgroup"))
        try writeInfo(displayName: "Alpha", to: firstChild.appendingPathComponent("Info.ulgroup"))
        try writeInfo(displayName: "Beta", to: secondChild.appendingPathComponent("Info.ulgroup"))
        try titledSheet("First Note").write(to: firstChild.appendingPathComponent("first.ulysses/Content.xml"), atomically: true, encoding: .utf8)
        try titledSheet("Second Note").write(to: secondChild.appendingPathComponent("second.ulysses/Content.xml"), atomically: true, encoding: .utf8)

        let output = root.appendingPathComponent("Output")
        _ = try await Exporter().run(input: input.path, output: output.path, allowUnknownFormat: true)

        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("Store/Same Parent [one]/Alpha/First Note.textbundle").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("Store/Same Parent [two]/Beta/Second Note.textbundle").path))
    }

    func testImageFirstTitleAndParenthesizedAssetProduceValidMarkdown() async throws {
        let root = try temporaryDirectory()
        let input = root.appendingPathComponent("Backup.ulbackup")
        let sheet = input.appendingPathComponent("Store.ulstoragebackup/Content/Unfiled-ulgroup/image.ulysses")
        let media = sheet.appendingPathComponent("Media")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try Data("image".utf8).write(to: media.appendingPathComponent("Cover (1).asset123.png"))
        try contentXML("""
        <sheet>
        <string xml:space="preserve">
        <p><element kind="image"><attribute identifier="image">asset123</attribute><attribute identifier="description">Cover Image</attribute></element></p>
        </string>
        </sheet>
        """).write(to: sheet.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)

        let output = root.appendingPathComponent("Output")
        _ = try await Exporter().run(input: input.path, output: output.path, allowUnknownFormat: true)

        let markdown = try String(contentsOf: output.appendingPathComponent("Inbox (Ulysses Group)/Cover Image.textbundle/text.markdown"), encoding: .utf8)
        XCTAssertTrue(markdown.contains("![Cover Image](assets/Cover%20%281%29.asset123.png)"))
    }

    func testAnalyzeIsDryRunAndReturnsSupportJSON() async throws {
        let root = try temporaryDirectory()
        let input = root.appendingPathComponent("Backup.ulbackup")
        let sheet = input.appendingPathComponent("Store.ulstoragebackup/Content/Unfiled-ulgroup/missing.ulysses")
        let output = root.appendingPathComponent("Output")
        try FileManager.default.createDirectory(at: sheet, withIntermediateDirectories: true)
        try contentXML("""
        <sheet>
        <string xml:space="preserve">
        <p><tags><tag kind="heading1"># </tag></tags>Dry Run</p>
        <p><element kind="image"><attribute identifier="image">not-found</attribute></element></p>
        </string>
        </sheet>
        """).write(to: sheet.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)

        let analysis = try await Exporter().analyze(input: input.path, allowUnknownFormat: true)

        XCTAssertEqual(analysis.summary.sheets, 1)
        XCTAssertEqual(analysis.summary.missingMedia, 1)
        XCTAssertTrue(analysis.reportMarkdown.contains("# Ulysses Export Report"))
        XCTAssertTrue(analysis.supportJSON.contains("\"missingMedia\" : 1"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testRealBackupSmokeWhenEnvironmentIsProvided() async throws {
        guard let path = ProcessInfo.processInfo.environment["ULYSSES_BACKUP_PATH"], !path.isEmpty else {
            throw XCTSkip("Set ULYSSES_BACKUP_PATH to run the private real-backup smoke test.")
        }

        let analysis = try await Exporter().analyze(input: path)

        XCTAssertGreaterThan(analysis.summary.sheets, 0)
        XCTAssertTrue(analysis.reportMarkdown.contains("# Ulysses Export Report"))
        XCTAssertTrue(analysis.supportJSON.contains("\"counts\""))
    }

    func testStrictFormatAcceptsVerifiedUlysses40Structure() async throws {
        let input = try verifiedBackup(sheetXML: titledSheet("Verified"))

        let analysis = try await Exporter().analyze(input: input.path)

        XCTAssertEqual(analysis.summary.sheets, 1)
        XCTAssertTrue(analysis.supportJSON.contains("\"verified\" : true"))
    }

    func testStrictFormatRejectsStructuralSchemaDrift() async throws {
        let variants = [
            "<sheet><string><p>Body</p></string><future-content /></sheet>",
            "<sheet><string><p>Body</p></string><attachment type=\"future\">x</attachment></sheet>"
        ]
        for xml in variants {
            let input = try verifiedBackup(sheetXML: contentXML(xml))
            do {
                _ = try await Exporter().analyze(input: input.path)
                XCTFail("Expected unverified format rejection")
            } catch let error as ExportError {
                guard case .unverifiedFormat = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }

    func testStrictFormatRejectsUnknownMarkupGrammar() async throws {
        let input = try verifiedBackup(sheetXML: contentXML("""
        <sheet>
          <markup version="2" identifier="custom"><tag definition="heading1" pattern="!" /></markup>
          <string><p>Body</p></string>
        </sheet>
        """))

        do {
            _ = try await Exporter().analyze(input: input.path)
            XCTFail("Expected unknown markup grammar rejection")
        } catch let error as ExportError {
            guard case .unverifiedFormat(let reasons) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(reasons.joined().contains("markup"))
        }
    }

    func testStrictFormatRejectsNewStoreVersionAndChangedPlistType() async throws {
        let root = try temporaryDirectory()
        let input = root.appendingPathComponent("Backup.ulbackup")
        let content = input.appendingPathComponent("Store.ulstoragebackup/Content")
        let sheet = content.appendingPathComponent("one.ulysses")
        try FileManager.default.createDirectory(at: sheet, withIntermediateDirectories: true)
        try titledSheet("Changed Store").write(to: sheet.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)
        try plist(displayNameValue: "<array/>", storeVersion: 2)
            .write(to: content.appendingPathComponent("Info.ulgroup"), atomically: true, encoding: .utf8)

        do {
            _ = try await Exporter().analyze(input: input.path)
            XCTFail("Expected unverified format rejection")
        } catch let error as ExportError {
            guard case .unverifiedFormat(let reasons) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(reasons.joined().contains("storeFormatVersion"))
            XCTAssertTrue(reasons.joined().contains("displayName"))
        }
    }

    func testStrictFormatRejectsMissingOrRenamedContent() async throws {
        for packageName in ["missing.ulysses", "renamed.ulysses2"] {
            let root = try temporaryDirectory()
            let input = root.appendingPathComponent("Backup.ulbackup")
            let content = input.appendingPathComponent("Store.ulstoragebackup/Content")
            try FileManager.default.createDirectory(at: content.appendingPathComponent(packageName), withIntermediateDirectories: true)
            try plist(displayNameValue: "<string>Store</string>", storeVersion: 1)
                .write(to: content.appendingPathComponent("Info.ulgroup"), atomically: true, encoding: .utf8)
            do {
                _ = try await Exporter().analyze(input: input.path)
                XCTFail("Expected missing or renamed content rejection")
            } catch let error as ExportError {
                guard case .unverifiedFormat = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }

    func testStrictFormatRejectsMixedStoreVersions() async throws {
        let input = try verifiedBackup(sheetXML: titledSheet("Mixed"))
        let second = input.appendingPathComponent("Second.ulstoragebackup/Content")
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try plist(displayNameValue: "<string>Second</string>", storeVersion: 2)
            .write(to: second.appendingPathComponent("Info.ulgroup"), atomically: true, encoding: .utf8)

        do {
            _ = try await Exporter().analyze(input: input.path)
            XCTFail("Expected mixed store version rejection")
        } catch let error as ExportError {
            guard case .unverifiedFormat(let reasons) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(reasons.joined().contains("2"))
        }
    }

    func testStrictFormatReportsMalformedOptionalPlistMetadata() async throws {
        let input = try verifiedBackup(sheetXML: titledSheet("Malformed Metadata"))
        let info = input.appendingPathComponent("Store.ulstoragebackup/Content/Broken-ulgroup/Info.ulgroup")
        try FileManager.default.createDirectory(at: info.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "<plist><dict><key>storeFormatVersion</key>".write(to: info, atomically: true, encoding: .utf8)

        let analysis = try await Exporter().analyze(input: input.path)

        XCTAssertTrue(analysis.supportJSON.contains("\"malformedPlistFiles\" : 1"))
        XCTAssertTrue(analysis.reportMarkdown.contains("Store.ulstoragebackup/Content/Broken-ulgroup/Info.ulgroup"))
    }

    func testMalformedXMLVariantsThrowWithoutCrashing() throws {
        let variants = [
            "",
            "<sheet>",
            "<sheet><string></sheet>",
            "<sheet><string>&invalid;</string></sheet>",
            "<sheet><attachment type=\"note\"><string></attachment></sheet>"
        ]
        for xml in variants {
            let url = URL(fileURLWithPath: "/synthetic/Content.xml")
            XCTAssertThrowsError(try UlyssesSheetParser(contentURL: url).parse(Data(xml.utf8)))
        }
    }

    func testMalformedOrMissingContentNeverPublishesPartialOutput() async throws {
        let root = try temporaryDirectory()
        let input = root.appendingPathComponent("Backup.ulbackup")
        let content = input.appendingPathComponent("Store.ulstoragebackup/Content")
        let good = content.appendingPathComponent("good.ulysses")
        let bad = content.appendingPathComponent("bad.ulysses")
        try FileManager.default.createDirectory(at: good, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        try titledSheet("Good").write(to: good.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)
        try "<sheet><string>broken".write(to: bad.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)
        try plist(displayNameValue: "<string>Store</string>", storeVersion: 1)
            .write(to: content.appendingPathComponent("Info.ulgroup"), atomically: true, encoding: .utf8)
        let output = root.appendingPathComponent("Output")

        do {
            _ = try await Exporter().run(input: input.path, output: output.path, allowUnknownFormat: true)
            XCTFail("Expected malformed XML failure")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path)
            XCTAssertFalse(leftovers.contains { $0.contains("export-ulysses-") })
        }
    }

    func testAnonymousSupportReportContainsNoTitlesPathsOrURLs() async throws {
        let xml = contentXML("""
        <sheet>
        <string><p><tags><tag kind="heading1"># </tag></tags>Private Note Title</p>
        <p><element kind="image"><attribute identifier="URL">file:///private/secret/photo.jpg</attribute></element></p></string>
        </sheet>
        """)
        let input = try verifiedBackup(sheetXML: xml)

        let analysis = try await Exporter().analyze(
            input: input.path,
            commandLine: ["export-ulysses", "doctor", "--backup", input.path]
        )

        XCTAssertFalse(analysis.supportJSON.contains("Private Note Title"))
        XCTAssertFalse(analysis.supportJSON.contains("photo.jpg"))
        XCTAssertFalse(analysis.supportJSON.contains("file:///"))
        XCTAssertFalse(analysis.supportJSON.contains(input.path))
        XCTAssertTrue(analysis.supportJSON.contains("external-file-url"))
        XCTAssertTrue(analysis.reportMarkdown.contains("Private Note Title"))
    }

    private func contentXML(_ body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        \(body)
        """
    }

    private func verifiedBackup(sheetXML: String) throws -> URL {
        let root = try temporaryDirectory()
        let input = root.appendingPathComponent("Backup.ulbackup")
        let content = input.appendingPathComponent("Store.ulstoragebackup/Content")
        let sheet = content.appendingPathComponent("one.ulysses")
        try FileManager.default.createDirectory(at: sheet, withIntermediateDirectories: true)
        try sheetXML.write(to: sheet.appendingPathComponent("Content.xml"), atomically: true, encoding: .utf8)
        try plist(displayNameValue: "<string>Store</string>", storeVersion: 1)
            .write(to: content.appendingPathComponent("Info.ulgroup"), atomically: true, encoding: .utf8)
        return input
    }

    private func plist(displayNameValue: String, storeVersion: Int) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
          <key>displayName</key>\(displayNameValue)
          <key>storeFormatVersion</key><integer>\(storeVersion)</integer>
        </dict></plist>
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

    private func writeInfo(
        displayName: String,
        sheetClusters: [[String]] = [],
        childOrder: [String] = [],
        icon: String? = nil,
        tint: String? = nil,
        countingGoal: [String: String] = [:],
        to url: URL
    ) throws {
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
        let childOrderXML = childOrder.isEmpty ? "" : """

          <key>childOrder</key>
          <array>
          \(childOrder.map { "<string>\($0)</string>" }.joined(separator: "\n"))
          </array>
        """
        let iconXML = icon.map { "\n  <key>userIconName</key>\n  <string>\($0)</string>" } ?? ""
        let tintXML = tint.map { "\n  <key>userTintColor</key>\n  <string>\($0)</string>" } ?? ""
        let countingGoalXML = countingGoal.isEmpty ? "" : """

          <key>countingGoal</key>
          <dict>
          \(countingGoal.sorted(by: { $0.key < $1.key }).map { "<key>\($0.key)</key>\n<string>\($0.value)</string>" }.joined(separator: "\n"))
          </dict>
        """
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict>
          <key>displayName</key>
          <string>\(displayName)</string>\(sheetClustersXML)\(childOrderXML)\(iconXML)\(tintXML)\(countingGoalXML)
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
