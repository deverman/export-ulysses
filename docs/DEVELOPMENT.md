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
- `main.swift`: two-command CLI only
- `Sources/ExportUlyssesApp`: SwiftUI presentation, native panels, progress, and FSNotes launch actions; no migration parsing or writing logic

Do not weaken a compatibility gate to accommodate a new fixture. Add a versioned reader or expand the Ulysses 40 contract only with evidence from that exact version.
