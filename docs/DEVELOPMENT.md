# Development

Requires macOS 26 Tahoe and Swift 6.3.2 or newer.

```sh
swift package resolve
swift build
swift test
swift run ExportUlyssesApp
```

Swift Argument Parser 1.8.2 is the only package dependency and is the latest release as of July 2026. Ulysses ordered mixed-content XML uses Foundation `XMLParser`; plist metadata uses `PropertyListSerialization`.

The local TextBundle writer deliberately has a small contract: create TextBundle v2 `info.json`, `text.markdown`, `assets/`, relative links, and source dates. Output validation tests that contract against FSNotes expectations. Shiny Frog TextBundle is mature but not a clean SwiftPM dependency; `mcritz/TextBundle` does not provide the FSNotes metadata writer required here.

Architecture boundaries:

- `FormatCompatibility.swift`: content-free fingerprints, compatibility policy, backup discovery, versioned reader protocol
- `Exporter.swift`: Ulysses 40 reader, sheet preparation, Markdown rendering, media resolution, migration orchestration
- `MigrationNotes.swift`: consolidated human and private migration indexes
- `OutputValidation.swift`: staging transaction and final TextBundle validation
- `Ulysses40BackupReader.swift`: Ulysses 40 package discovery and metadata reading
- `SheetExporter.swift`: one-sheet preparation and export accounting
- `MigrationLayout.swift`: deterministic group paths, ordering, naming, and TextBundle writing
- `SheetRendering.swift`: Ulysses XML parsing, Markdown rendering, and media resolution
- `ExportReporting.swift`: visible migration report and privacy-safe support JSON
- `main.swift`: two-command CLI only
- `Sources/ExportUlyssesApp`: SwiftUI presentation, native panels, progress, and FSNotes launch actions; no migration parsing or writing logic
- `ExportUlysses.xcodeproj`: sandboxed `APP_STORE` target and shared archive scheme; links the local `UlyssesExporter` package product
- `ReleaseToolKit` and `release-tool`: testable direct-release and App Store archive automation; intentionally separate from the exporter and app

Do not weaken a compatibility gate to accommodate a new fixture. Add a versioned reader or expand the Ulysses 40 contract only with evidence from that exact version.

## Release Tool

Release automation is a SwiftPM executable rather than shell code:

```sh
swift run -c release release-tool package 1.0.0 arm64
DEVELOPMENT_TEAM=YOURTEAMID swift run -c release release-tool archive-app-store 1.0.0 1
```

`package` builds the CLI and direct app, checks the compiled CLI version, assembles the app bundle, optionally signs, notarizes and staples the app, creates a ZIP, and writes its SHA-256 file under `dist/`. Set `CODESIGN_IDENTITY` to sign. Notarization is enabled only when `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_PASSWORD` are all set; a partial configuration or notarization without a signing identity fails before the build starts.

`archive-app-store` requires `DEVELOPMENT_TEAM` and opens the completed archive in Organizer. Pass `--no-open` for unattended automation or `--archive-path PATH` to select a different output.

Release commands must run from the repository root. The implementation lives in `ReleaseToolKit` so naming, validation, and credential policy can be tested without invoking signing or Xcode.
