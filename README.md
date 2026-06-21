# export-ulysses

Exports a Ulysses 40 backup into FSNotes-readable TextBundle notes.

This tool targets Ulysses 40 on macOS 26 Tahoe with Swift 6.3.2 or newer. It reads Ulysses backup packages (`.ulbackup`) instead of copying the iCloud Drive folder, because the backup `Content.xml` and `Info.ulgroup` files include Ulysses sidebar notes, comments, annotations, attachments, keywords, sheet order, glued sheets, material sheets, goals, group icons, and other migration metadata.

## Migrate In 3 Steps

1. Build or run the tool:

   ```sh
   git clone git@github.com:deverman/export-ulysses.git
   cd export-ulysses
   swift run export-ulysses --help
   ```

2. Check the backup before writing anything:

   ```sh
   swift run export-ulysses \
     "$HOME/Library/Group Containers/X5AZV975AG.com.soulmen.shared/Ulysses/Backups/Latest Backup.ulbackup" \
     --keep-groups \
     --doctor \
     --analyze
   ```

3. Export to a new FSNotes folder:

   ```sh
   swift run export-ulysses \
     "$HOME/Library/Group Containers/X5AZV975AG.com.soulmen.shared/Ulysses/Backups/Latest Backup.ulbackup" \
     ./FSNotesImport \
     --keep-groups \
     --jobs 2
   ```

Then add `FSNotesImport` as an FSNotes folder. The export writes a visible `Ulysses Export Report.textbundle` and a privacy-safe `.export-ulysses/ulysses-export-report.json` support report in a hidden folder so FSNotes does not show JSON as a note.

## Commands And Options

Arguments:

- `input`: a Ulysses `.ulbackup` folder, usually `Latest Backup.ulbackup`
- `output`: the folder where FSNotes TextBundles should be written; required for export, optional for `--analyze`

Options:

- `--keep-groups`: preserve Ulysses group folders in the output
- `--ignore <group>`: skip matching Ulysses groups
- `--jobs <count>`: convert sheets concurrently; default is `2`
- `--analyze`: scan the backup and print a migration report without writing TextBundles
- `--doctor`: run preflight checks for the backup path, output folder, markup, and asset references
- `--verbose`: print additional discovery/export progress

## Fidelity Matrix

| Ulysses data | FSNotes export behavior |
| --- | --- |
| Sheet text | Preserved in `text.markdown` |
| Headings, lists, links, emphasis, strong, code, footnotes, highlights, deletions | Converted to Markdown where Markdown can represent them |
| Comments and annotations | Preserved visibly in Markdown comments or inline annotation text |
| Sidebar notes | Preserved in `## Ulysses Sidebar Notes` |
| Sidebar file attachments | Copied to `assets/` and linked from `## Ulysses Attachments` |
| Inline images | Copied to `assets/` and linked with relative Markdown paths |
| Keywords | Written as visible FSNotes-searchable hashtags |
| Material sheets | Tagged `#ulysses/material` |
| Glued sheets | Tagged `#ulysses/glued` and listed in distinct `Ulysses Sheet Order: Group / Path` notes |
| Archive, Templates, Trash | Preserved as folders and tagged `#ulysses/archive`, `#ulysses/template`, or `#ulysses/trash` |
| Favorites | Tagged `#ulysses/favorite` when Ulysses exposes favorite metadata in sheet XML |
| Group icons, colors, goals, activity counts | Preserved in distinct `Ulysses Metadata: Group / Path` notes |
| Ulysses sheet order | Preserved in `Ulysses Sheet Order: Group / Path` notes using FSNotes `[[wikilinks]]` |
| Creation and modification dates | Written to TextBundle `info.json` and applied to bundle files |
| FSNotes pins and folder sort settings | Not written; these are FSNotes app-internal settings, not portable TextBundle metadata |

Ulysses-only data that FSNotes cannot model directly is made visible in Markdown instead of hidden in custom JSON.

## Output Shape

Each Ulysses sheet becomes one FSNotes-readable `.textbundle`:

```text
Example.textbundle/
  text.markdown
  info.json
  assets/
```

`info.json` follows TextBundle v2 and includes FSNotes-friendly fields such as `flatExtension`, `created`, and `modified`.

## Troubleshooting

- Run `--doctor --analyze` first. It does not write notes and reports missing assets, unsupported XML nodes, duplicate output titles, archive/template/trash counts, and Ulysses metadata keys.
- If the backup path cannot be read, grant Full Disk Access to Terminal, iTerm, or the app running this command.
- If FSNotes preview does not show an image, check whether the image appears in `assets/` and whether the Markdown link starts with `assets/`.
- Duplicate Ulysses titles are preserved as separate TextBundles with numeric suffixes. The report counts how many were renamed.
- Missing media references are preserved as report entries with the affected note title and reference. Bare filenames usually mean an imported/local image was never stored in the Ulysses package. Mobile `file://` references usually point to transient iOS app storage and cannot be recovered from a Ulysses backup.
- The support report intentionally excludes note text. Share `.export-ulysses/ulysses-export-report.json` when filing a bug, not your Ulysses backup.

## Real Library Validation

Validated against:

```text
~/Library/Group Containers/X5AZV975AG.com.soulmen.shared/Ulysses/Backups/Latest Backup.ulbackup
```

Recent dry-run validation found:

- 2,631 sheets
- 265 sidebar notes
- 55 sidebar file attachments
- 597 inline images
- 466 keywords
- 20 material sheets
- 206 glued sheets
- 137 sheet order notes
- about 40-50 group metadata notes for groups with visible Ulysses-only metadata such as icons, colors, goals, activity, or archive/template/trash roles
- 30 missing media references
- 0 unsupported XML nodes

## Dependency Notes

The exporter intentionally keeps the Ulysses sheet parser on Foundation `XMLParser`. Ulysses sheet XML is ordered mixed content, so a streaming parser is a better fit than a generic Codable XML mapping layer for this version.

TextBundle writing is implemented locally and covered by tests. Shiny Frog's TextBundle framework is mature but not SwiftPM-native; `mcritz/TextBundle` is SwiftPM-native but does not cover the FSNotes metadata shape this exporter writes.
