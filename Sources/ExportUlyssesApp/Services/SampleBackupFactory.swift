import Foundation

enum SampleBackupFactory {
    static func create() throws -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Export Ulysses", isDirectory: true)
            .appendingPathComponent("Sample Backup.ulbackup", isDirectory: true)
        let content = root.appendingPathComponent("Ubiquitous Library.ulstoragebackup/Content", isDirectory: true)
        let sheet = content.appendingPathComponent("Unfiled-ulgroup/sample.ulysses", isDirectory: true)
        try FileManager.default.createDirectory(at: sheet, withIntermediateDirectories: true)

        try groupInfo.write(
            to: content.appendingPathComponent("Info.ulgroup"),
            atomically: true,
            encoding: .utf8
        )
        try sheetXML.write(
            to: sheet.appendingPathComponent("Content.xml"),
            atomically: true,
            encoding: .utf8
        )
        return root
    }

    private static let groupInfo = """
    <?xml version="1.0" encoding="UTF-8"?>
    <plist version="1.0"><dict>
      <key>displayName</key><string>Notes</string>
      <key>storeFormatVersion</key><integer>1</integer>
    </dict></plist>
    """

    private static let sheetXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <sheet>
      <markup version="1" identifier="markdownxl" displayName="Markdown XL">
        <tag definition="heading1" pattern="#"/>
        <tag definition="strong" startPattern="**" endPattern="**"/>
      </markup>
      <string xml:space="preserve">
        <p><tags><tag kind="heading1"># </tag></tags>Sample Ulysses Sheet</p>
        <p>This sample demonstrates the same preflight, TextBundle writing, and validation path used for a real backup.</p>
        <p><element kind="strong">No private writing leaves your Mac.</element></p>
      </string>
      <attachment type="keywords">sample,migration</attachment>
      <attachment type="note"><string xml:space="preserve"><p>Sample sidebar note.</p></string></attachment>
    </sheet>
    """
}
