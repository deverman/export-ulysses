# export-ulysses

Migrate a Ulysses 40 backup into a validated FSNotes library without dropping sheets, sidebar notes, comments, attachments, images, groups, order, or Trash state.

Verified with Ulysses 40 build 83290, macOS 26 Tahoe, Swift 6.3.2, TextBundle v2, and FSNotes. Format changes are reported during preflight: optional metadata drift produces warnings, while structural changes that could silently lose sheet content stop migration by default. Maintainers can inspect an unverified format with the CLI's `--allow-unknown-format` override.

## Migrate In 3 Steps

1. Create a fresh Ulysses backup, separately export any Ulysses **External Folders**, and back up your current FSNotes storage. Ulysses enables local backups automatically, so there is normally nothing to configure, but the app must have been open for at least five minutes before an automatic backup is created. For a guaranteed current backup, choose **Ulysses > Settings > Backup > Backup now**. Ulysses backups do not contain External Folders. See [Ulysses' backup guide](https://help.ulysses.app/backups).

2. Download the notarized release from [GitHub Releases](https://github.com/deverman/export-ulysses/releases). Open **Export Ulysses.app** for the guided migration, or use the included `export-ulysses` command-line tool. Both use the same tested migration library.

   To build from source instead:

   ```sh
   git clone https://github.com/deverman/export-ulysses.git
   cd export-ulysses
   swift build -c release
   alias export-ulysses="$PWD/.build/release/export-ulysses"
   ```

3. In **Export Ulysses.app**, confirm the discovered backup and destination, select **Run Preflight**, review the results, and select **Migrate to FSNotes**.

   CLI users can run the equivalent workflow:

   ```sh
   export-ulysses doctor --output "$HOME/Documents/FSNotes Ulysses Migration"
   export-ulysses migrate "$HOME/Documents/FSNotes Ulysses Migration"
   ```

The newest local `.ulbackup` is selected automatically. Pass `--backup "/path/to/Backup.ulbackup"` to use another backup. The default is `--jobs 2`; advanced users can raise it explicitly.

If automatic discovery reports that no backup exists, leave Ulysses open for at least five minutes or use **Backup now**, then rerun `doctor`. On another Mac or an exported backup, pass its path with `--backup`; local Ulysses backups do not sync between devices.

### Add The Migration To FSNotes

**If you already use FSNotes, keep your current Default Storage.** The least disruptive approach is to choose that existing storage folder as the destination parent in Export Ulysses. The app creates a new `FSNotes Ulysses Migration` child folder, so imported notes stay together and FSNotes discovers them without replacing or mixing them with your existing files. If you exported elsewhere, add the migration folder as an external folder for review, or move the complete folder under your existing Default Storage while FSNotes is closed.

FSNotes only treats its configured Trash folder as system Trash. To retain the Ulysses trash state in an existing library, first verify **FSNotes > Settings > Advanced > Trash**, then move the TextBundles inside the migration's `Trash` folder into that existing FSNotes Trash folder. Review them before using **Empty Trash**. Leaving them in the nested migration `Trash` folder preserves the files on disk, but FSNotes may not display them.

**For a new or empty FSNotes installation**, select the migration folder as **FSNotes > Settings > General > Default Storage**, then set **Settings > Advanced > Trash** to its `Trash` subfolder. This gives migrated Ulysses Inbox and Trash sheets native FSNotes Inbox and Trash behavior.

## What Is Preserved

| Ulysses data | FSNotes result |
| --- | --- |
| Sheets and Markdown-compatible formatting | One TextBundle v2 note per sheet |
| Inline images and file attachments | Copied into each bundle's `assets/` and linked relatively |
| Sidebar notes, comments, annotations | Visible Markdown sections or markers |
| Keywords | Searchable hashtags |
| Groups and projects | FSNotes folders with deterministic collision handling |
| Inbox | Root when used as a new Default Storage; contained in the migration folder when added to an existing library |
| Trash | Exported to `Trash/`; use it as the new library's Trash or move its contents into an existing library's configured Trash |
| Archive and Templates | Folders plus `#ulysses/archive` and `#ulysses/template` |
| Material, glued, favorite status | `#ulysses/material`, `#ulysses/glued`, and `#ulysses/favorite` |
| Sheet order and glued clusters | Consolidated `Ulysses Library Map` with FSNotes links |
| Saved filters | Visible migration note with scope and query description |
| Group icons, colors, goals, activity | Consolidated visible metadata note |
| Creation and modification dates | TextBundle metadata and filesystem dates |

FSNotes has no portable TextBundle field for native pins, Ulysses goals, group colors/icons, or per-folder sort settings. Those values are kept visibly rather than pretending FSNotes can recreate the Ulysses UI.

## Safety Model

- `doctor` performs format fingerprinting, a complete dry run, destination checks, and a free-space check.
- `migrate` always includes all groups and sheets. There is no omission flag.
- Every sheet is parsed before publishing output.
- Output is built in a hidden staging directory, validated, and moved into place only after all TextBundles and asset links pass.
- A malformed sheet, changed structural XML node, changed plist type, missing `Content.xml`, or unknown store version stops the migration.
- `.export-ulysses/ulysses-export-report.json` is anonymous and excludes titles, filenames, URLs, filesystem paths, and note contents.
- The private `.export-ulysses/manifest.json` and visible Ulysses Export Report contain actionable migration details. Do not attach those publicly without reviewing them.

## Output

```text
FSNotes Ulysses Migration/
  A Sheet.textbundle/
    text.markdown
    info.json
    assets/
  Trash/
  Archive (Ulysses)/
  _Ulysses Migration/
  .export-ulysses/
```

The `_Ulysses Migration` folder contains at most five companion notes: export report, library map, group metadata, favorites, and saved filters. After reviewing it in FSNotes, disable **Show notes in Notes and Todo lists** for that folder.

## Commands

```text
export-ulysses doctor [--backup PATH] [--output PATH] [--jobs 2]
export-ulysses migrate OUTPUT [--backup PATH] [--jobs 2]
export-ulysses --version
```

`--allow-unknown-format` is a developer escape hatch, not a migration recommendation. It permits inspection of format drift but cannot make an unknown schema trustworthy.

## Guided Mac App

The release archive includes **Export Ulysses.app** for users who prefer not to work in Terminal. It automatically discovers the newest local backup, provides native backup and destination pickers, runs the same preflight checks as the CLI, displays migration totals and progress, and publishes the output only after the shared validator passes.

The app is a separate executable target over `UlyssesExporter`; the CLI remains fully supported and does not launch or depend on SwiftUI.

## Help

- [Troubleshooting and FAQ](docs/TROUBLESHOOTING.md)
- [Compatibility policy](docs/COMPATIBILITY.md)
- [Real-library validation](docs/VALIDATION.md)
- [Development and dependencies](docs/DEVELOPMENT.md)
- [Release tool](docs/DEVELOPMENT.md#release-tool)
- [Mac App Store architecture and submission](docs/APP_STORE.md)
- [Contributing](CONTRIBUTING.md)
- [Security and privacy](SECURITY.md)

When filing an issue, attach only `.export-ulysses/ulysses-export-report.json` unless a maintainer specifically requests privately reviewed evidence.

Export Ulysses is an independent migration utility and is not affiliated with the developers of Ulysses or FSNotes. Product names and trademarks belong to their respective owners.
