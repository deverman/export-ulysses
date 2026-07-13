# Validation

The private integration test is enabled with `ULYSSES_BACKUP_PATH` and never commits user data:

```sh
ULYSSES_BACKUP_PATH="/path/to/Latest Backup.ulbackup" swift test
```

The Ulysses 40 build 83290 validation library used during development contains 2,631 sheets, 265 attached sheet notes, 173 inline comments, 394 annotations, 55 sidebar file attachments, 601 inline images, 466 keywords, 20 material sheets, 206 glued sheets, 57 archive sheets, 29 current non-trash favorites, 1 active saved filter, and 1,051 Trash sheets. Its latest dry run reported 31 source-missing media references, zero unsupported cosmetic XML nodes, and one corrupt optional `Info.ulgroup` inside Trash that is surfaced as a metadata warning.

Release validation must pass:

- unit and schema-drift tests
- strict doctor fingerprint
- source package, parsed sheet, and exported sheet count equality
- TextBundle v2 layout and JSON checks
- zero broken relative asset links
- Ulysses Trash count equal to TextBundles under FSNotes `Trash/`
- anonymous support report privacy assertions
