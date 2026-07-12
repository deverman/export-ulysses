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

Then add `FSNotesImport` as an FSNotes folder. Migration-only notes are kept together under `_Ulysses Migration`; after reviewing them, you can disable **Show notes in Notes and Todo lists** for that one FSNotes folder. Hidden machine-readable files are written under `.export-ulysses`.

The output folder must be empty. This prevents an accidental second run from silently creating thousands of duplicate notes with numeric suffixes.

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
| Comments and annotations | Preserved as visible `Ulysses comment` or `Ulysses annotation` markers, including in FSNotes preview |
| Sidebar notes | Preserved in `## Ulysses Sidebar Notes` |
| Sidebar file attachments | Copied to `assets/` and linked from `## Ulysses Attachments` |
| Inline images | Copied to `assets/` and linked with relative Markdown paths |
| Keywords | Written as visible FSNotes-searchable hashtags |
| Material sheets | Tagged `#ulysses/material` |
| Glued sheets | Tagged `#ulysses/glued` and shown as clusters in the consolidated library map |
| Archive, Templates, Trash | Preserved as folders and tagged `#ulysses/archive`, `#ulysses/template`, or `#ulysses/trash` |
| Favorites | Read from Ulysses `Content/favorites`, tagged `#ulysses/favorite`, and listed in `Ulysses Favorites` |
| Saved filters | Filter names, scopes, status, and query conditions are listed in `Ulysses Saved Filters` |
| Group icons, colors, goals, activity counts | Consolidated into `Ulysses Group Metadata` |
| Sheet and group order | Consolidated into `Ulysses Library Map` and the hidden manifest, including glued clusters and `childOrder` |
| Duplicate group names | Kept as separate folders; conflicting names receive a short stable Ulysses ID suffix and are mapped in the manifest |
| Creation and modification dates | Written to TextBundle `info.json` and applied to bundle files |
| FSNotes pins and folder sort settings | Not written; these are FSNotes app-internal settings, not portable TextBundle metadata |

Ulysses-only data that FSNotes cannot model directly is made visible in Markdown instead of hidden in custom JSON.

FSNotes links in migration notes target each exported filename through `fsnotes://find?id=...`. This keeps duplicate Ulysses titles as separate notes without allowing an order or favorites link to open the wrong one.

## Output Shape

Each Ulysses sheet becomes one FSNotes-readable `.textbundle`:

```text
Example.textbundle/
  text.markdown
  info.json
  assets/
```

`info.json` follows TextBundle v2 and includes FSNotes-friendly fields such as `flatExtension`, `created`, and `modified`.

The companion folder contains at most these five notes:

- `Ulysses Export Report`
- `Ulysses Library Map`
- `Ulysses Group Metadata`
- `Ulysses Favorites`, when favorites exist
- `Ulysses Saved Filters`, when filters exist

`.export-ulysses/manifest.json` is the authoritative migration map. It includes note titles and source-relative paths and is therefore private. `.export-ulysses/ulysses-export-report.json` excludes note contents and is the file intended for support requests.

## Troubleshooting

- Run `--doctor --analyze` first. It does not write notes and reports missing assets, unsupported XML nodes, duplicate output titles, archive/template/trash counts, and Ulysses metadata keys.
- If the backup path cannot be read, grant Full Disk Access to Terminal, iTerm, or the app running this command.
- If FSNotes preview does not show an image, check whether the image appears in `assets/` and whether the Markdown link starts with `assets/`.
- Duplicate Ulysses titles are preserved as separate TextBundles with numeric suffixes. The report counts how many were renamed.
- Same-named Ulysses groups remain separate. The actual Ulysses Archive keeps `Archive`; an unrelated conflicting group receives a stable suffix such as `Archive [671ab37b]`.
- If the output-folder check fails, choose a new empty folder. The exporter intentionally does not append to or overwrite an earlier migration.
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
- 601 inline images
- 466 keywords
- 20 material sheets
- 206 glued sheets
- 57 archive sheets
- 41 active favorites
- 1 active saved filter, with deleted filters retained in the migration record
- 1 consolidated sheet-order note
- 1 consolidated group-metadata note
- 31 missing media references
- 0 unsupported XML nodes

## Dependency Notes

The exporter intentionally keeps the Ulysses sheet parser on Foundation `XMLParser`. Ulysses sheet XML is ordered mixed content, so an event-driven parser is a better fit than a generic Codable XML mapping layer. Ulysses property lists are handled by Foundation property-list APIs, including binary favorites files and filter definitions.

TextBundle writing is implemented locally and covered by conformance tests. Shiny Frog's TextBundle framework is mature but not SwiftPM-native; `mcritz/TextBundle` is SwiftPM-native but does not cover the FSNotes metadata shape this exporter writes. Adding either would introduce an adapter without removing the Ulysses-specific migration code.

Swift Argument Parser is the only package dependency and is pinned to the latest release resolved by SwiftPM. The rest uses macOS Foundation APIs. The migration-note implementation is separated into `MigrationNotes.swift` so backup discovery, XML rendering, and FSNotes presentation do not grow into one subsystem.
