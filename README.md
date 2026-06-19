# export-ulysses

Exports a Ulysses backup into FSNotes-readable TextBundle notes.

This tool targets Ulysses 40 on macOS 26 Tahoe. It reads Ulysses backup packages (`.ulbackup`) instead of only copying the iCloud Drive TextBundle folder, because the backup `Content.xml` files include Ulysses inspector/sidebar data such as notes, file attachments, keywords, comments, and media references.

## Installing

You need Swift 6.3.2 or newer.

```sh
git clone git@github.com:deverman/export-ulysses.git
cd export-ulysses
swift run export-ulysses --help
```

For repeated use, build a release binary:

```sh
swift build -c release
```

## Usage

```sh
swift run export-ulysses \
  "$HOME/Library/Group Containers/X5AZV975AG.com.soulmen.shared/Ulysses/Backups/Latest Backup.ulbackup" \
  ./FSNotesImport \
  --keep-groups \
  --jobs 4
```

Arguments:

- `input`: a Ulysses `.ulbackup` folder, usually `Latest Backup.ulbackup`
- `output`: the folder where FSNotes TextBundles should be written

Options:

- `--keep-groups`: preserve Ulysses group folders in the output
- `--ignore <group>`: skip matching Ulysses groups
- `--jobs <count>`: convert sheets concurrently
- `--verbose`: print additional discovery/export progress

## What Is Exported

Each Ulysses sheet becomes one FSNotes-readable `.textbundle`:

```text
Example.textbundle/
  text.markdown
  info.json
  assets/
```

The exporter preserves:

- Main sheet text
- Headings, lists, links, emphasis, strong text, inline code, comments, footnotes, highlights, and deleted text where Markdown can represent them
- Inline images and image descriptions
- Ulysses sidebar notes, written into a visible `## Ulysses Sidebar Notes` section
- Ulysses sidebar file attachments, copied to `assets/` and linked from `## Ulysses Attachments`
- Ulysses keywords, written into `## Ulysses Keywords`
- Ulysses tables, converted to Markdown tables
- Group hierarchy when `--keep-groups` is used
- FSNotes-compatible TextBundle `info.json`

Ulysses-only data that FSNotes cannot model directly is made visible in Markdown instead of hidden in custom JSON. FSNotes currently decodes only a small TextBundle metadata shape, so sidebar notes and keywords are intentionally rendered into the note body where FSNotes can display and search them.

## Known Degradations

- Ulysses inspector/sidebar placement is not preserved as UI; the data is preserved as visible Markdown sections.
- Ulysses image alignment and sizing hints are flattened to normal Markdown image links.
- Missing or stale media references are reported as `Missing media references`.
- Unsupported XML nodes are counted in the export summary so you can see whether additional Ulysses markup needs a converter.

## Real Library Validation

Validated against:

```text
~/Library/Group Containers/X5AZV975AG.com.soulmen.shared/Ulysses/Backups/Latest Backup.ulbackup
```

The validation run exported:

- 2,631 sheets
- 265 sidebar notes
- 56 sidebar file attachments
- 597 inline images
- 466 keywords
- 570 copied asset files

Run the export into a temporary folder first, then point FSNotes at the resulting folder once the report looks right.
