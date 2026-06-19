# export-ulysses

Exports your Ulysses 40 iCloud library into an FSNotes-friendly folder.

- Exports Ulysses 40 iCloud libraries that contain `.md` files and `.textbundle` packages.
- Preserves TextBundle packages intact so FSNotes can read note text, `info.json`, and `assets/`.
- Copies visible loose resource files such as images and PDFs.
- Runs exports concurrently with Swift structured concurrency.
- Exported files have creation and modification dates that match your notes.

## Installing

export-ulysses targets macOS 26 Tahoe and builds with Swift 6.3.2 plus the current `swift-argument-parser` package. You’ll need to [install Xcode](https://developer.apple.com/xcode/) or another Swift 6.3 toolchain to build it.

```
git clone git@github.com:kevboh/export-ulysses.git
cd export-ulysses
swift run export-ulysses --help
```

If you plan to do this often, you may want to build a release binary with `swift build -c release` and copy it into your PATH.

## Usage (--help)

```
USAGE: export-ulysses <input> <output> [--keep-groups] [--verbose] [--ignore <ignore> ...] [--jobs <jobs>]

ARGUMENTS:
  <input>                 The path to your Ulysses notes.
  <output>                The path you want to export notes to.

OPTIONS:
  --keep-groups           Create directories for each Ulysses Group, and export notes into them.
  -v, --verbose           Log export activity and debugging statements.
  --ignore <ignore> ...   Groups to ignore on export.
  --jobs <jobs>           Maximum number of items to export concurrently. Defaults to 2.
  -h, --help              Show help information.
```

### Okay, give me those input hints

Ulysses 40 iCloud Drive libraries may store sheets under `~/Library/Mobile Documents/com~apple~CloudDocs/Ulysses/`.

Example:

```
swift run export-ulysses "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Ulysses" ./FSNotesImport --keep-groups --jobs 2
```

### FSNotes Export

FSNotes supports `.textbundle` containers. This exporter therefore preserves Ulysses TextBundles instead of flattening them:

- `Example.textbundle/text.md`
- `Example.textbundle/info.json`
- `Example.textbundle/assets/`

Plain `.md` notes and visible loose files are copied as-is. Hidden Ulysses metadata folders and files are skipped.

The exporter has been smoke-tested against a Ulysses 40 iCloud Drive library at `~/Library/Mobile Documents/com~apple~CloudDocs/Ulysses/`, exporting 314 Markdown/TextBundle notes plus loose visible resources with `--keep-groups`.

## Caveats

This tool targets the Ulysses 40 iCloud Drive format. It intentionally does not support older `.ulysses/Content.xml` libraries.
