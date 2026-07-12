# Troubleshooting

## Before You Run It

1. In Ulysses, create a fresh backup or leave the app open long enough for its current backup to complete.
2. Export Ulysses External Folders separately; they are not in `.ulbackup` files.
3. Back up the current FSNotes Default Storage folder.
4. Choose a new empty destination with enough free disk space.
5. Run `export-ulysses doctor --output "/your/new/folder"`.

## FSNotes Shows No Inbox Or Trash

Select the export root as **FSNotes > Settings > General > Default Storage**. Adding it as an external folder does not give root notes Inbox semantics. Verify **Settings > Advanced > Trash** points to `<export root>/Trash`, then restart FSNotes.

FSNotes Empty Trash permanently deletes imported Ulysses Trash sheets. Review them first.

## Missing Images Or Attachments

The private `Ulysses Export Report` identifies the affected sheet and reference. A bare filename means the XML references an asset not present in the sheet package or backup-wide media index. A `file:///var/mobile/...` URL points to transient storage outside the backup, commonly an old Messages attachment. The exporter cannot recreate bytes that Ulysses did not save.

The anonymous support report includes only categories and counts, never the private title or URL.

## Duplicate Titles

Ulysses permits duplicate sheet titles. FSNotes stores each sheet as a separate file, so deterministic numeric suffixes preserve every note. Migration links use `fsnotes://find?id=...` and target the allocated filename.

## Archive, Templates, Favorites, Goals

The special archive is named `Archive (Ulysses)` to distinguish it from an ordinary group named Archive. Favorites, material, glued sheets, templates, and archive roles become visible tags and companion indexes. Goals, folder colors/icons, and saved filters have no native portable FSNotes equivalent and are retained in migration notes.

## Rerunning Or Updating

The exporter is a one-time migration, not an incremental sync. It refuses a non-empty output so a rerun cannot duplicate thousands of notes. Migrate into another new folder, compare the reports, and deliberately choose which library FSNotes should use.

## Full Disk Access

If the backup cannot be read, grant Full Disk Access to the terminal application running the command, restart that application, and rerun `doctor`. The error prints the exact unreadable path.

## Reporting A Problem

Run `export-ulysses --version` and `export-ulysses doctor`. Attach only `.export-ulysses/ulysses-export-report.json` or the JSON printed by doctor. State whether the export root is FSNotes Default Storage and whether its Trash path was verified.
