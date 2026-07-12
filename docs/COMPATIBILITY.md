# Compatibility

## Verified Input

The current reader is verified against Ulysses 40 build 83290 backups created on macOS. The compatibility fingerprint requires:

- `.ulysses/Content.xml` for every discovered sheet package
- XML root `sheet`, known structural top-level nodes, and the observed Markdown XL grammar versions 1-3
- known attachment types (`note`, `file`, `keywords`)
- numeric `storeFormatVersion` value `1`
- expected types for known group, favorites, and filter plist fields

Cosmetic inline or paragraph markup can be preserved as text and reported as unsupported. Structural changes block migration because silently guessing could lose whole attachments or metadata sections.

An unreadable optional group/filter/favorites plist is reported as a warning and its private relative path is retained. The exporter can still preserve sheets beneath a corrupt group by using fallback identity. A parseable plist whose known keys change type remains a hard compatibility failure.

## New Ulysses Versions

Run `export-ulysses doctor` before every migration. A newer Ulysses version is supported only after its anonymous fingerprint and representative fixtures are reviewed and a versioned reader accepts it. Do not normalize a new format into the Ulysses 40 reader merely to make the warning disappear.

`--allow-unknown-format` exists for maintainers investigating a new schema. It does not certify the output.

## Source Coverage Limitation

Ulysses documents that its backups exclude External Folders. The exporter cannot discover content that is absent from the backup. Export or copy External Folders separately before ending a Ulysses subscription.
