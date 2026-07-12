# Changelog

## 1.0.0 - Unreleased

- Migrate Ulysses 40 backups to validated FSNotes TextBundle v2 storage.
- Preserve sheet content, sidebar metadata, media, groups, order, roles, dates, Inbox, and Trash behavior.
- Add strict format fingerprinting, atomic staged output, anonymous diagnostics, backup auto-discovery, and `doctor` preflight.
- Add a separate guided SwiftUI app using the same migration library while retaining the full CLI workflow.
- Add an App Store Xcode target with sandboxed user-selected file access, security-scoped bookmarks, privacy disclosure, and an offline review demo.
- Replace shell release automation with the tested SwiftPM `release-tool` for direct packages and App Store archives.
- Fix the macOS backup picker incorrectly disabling valid `.ulbackup` packages when their UTI is dynamically resolved.
