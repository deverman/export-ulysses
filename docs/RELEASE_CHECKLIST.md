# Release Checklist

## Repository

- Merge the release candidate into the default branch.
- Confirm CI passes on `macos-26` and `macos-26-intel`.
- Confirm the App Store Xcode project and shared scheme are present in a fresh checkout.
- Update `CHANGELOG.md`, `ExportUlyssesVersion.current`, and the `vMAJOR.MINOR.PATCH` tag together.
- Confirm the repository description, topics, issue templates, privacy policy, and screenshots are current.

## GitHub Secrets

The **Signed Release** workflow needs these repository Actions secrets:

- `APPLE_CERTIFICATE_BASE64`: Developer ID Application certificate exported as a base64-encoded `.p12`.
- `APPLE_CERTIFICATE_PASSWORD`: password used when exporting the `.p12`.
- `KEYCHAIN_PASSWORD`: temporary CI keychain password.
- `CODESIGN_IDENTITY`: full Developer ID Application identity.
- `APPLE_ID`: Apple Account used by `notarytool`.
- `APPLE_TEAM_ID`: Apple Developer team identifier.
- `APPLE_APP_PASSWORD`: app-specific password for notarization.

The workflow validates the package before building ARM64 and Intel artifacts. Each artifact is signed, notarized, stapled, zipped, and checksummed. Publishing runs only after both architecture jobs succeed and both checksums verify, preventing a partial GitHub release. Keep **Publish as a GitHub prerelease** selected for the public beta.

## Clean Installation

1. Download both the ZIP and `.sha256` from GitHub Releases; do not test a local build.
2. Verify the checksum from the download directory with `shasum -a 256 -c FILE.zip.sha256`.
3. Extract the ZIP and open **Export Ulysses.app** on a Mac account that has not run a development build.
4. Confirm Gatekeeper opens the app without a bypass, the icon appears, and the sample migration completes.
5. Select a real `.ulbackup`, run preflight, and confirm the output count matches the source count.
6. Test both FSNotes paths: a child folder inside an existing Default Storage and a new empty Default Storage.
7. Review Trash behavior, image rendering, file dates, duplicate titles, and the visible migration report.
8. Run the included CLI's `doctor` and `migrate` commands from the extracted release.

## Public Announcement

Describe the first release as an open-source public beta verified with Ulysses 40 build 83290. Do not call it universally lossless. Use this promise:

> Export Ulysses preserves every recoverable item, reports anything it cannot map or find, and never silently publishes a partial migration.

Include the supported Ulysses version, macOS 26 requirement, FSNotes integration choices, privacy model, known limits, GitHub release link, and a request for anonymous support reports from other Ulysses 40 libraries.

Before posting to a community, read its current self-promotion rules. Make the Reddit post a technical migration report and request for testing rather than an advertisement. When contacting FSNotes, link the TextBundle fidelity matrix and clearly state that this is an independent project.
