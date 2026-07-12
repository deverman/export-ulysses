# Mac App Store Distribution

## Architecture

The repository has three presentation products over one migration engine:

- `UlyssesExporter`: format readers, migration policy, reports, atomic writing, and validation
- `export-ulysses`: unrestricted command-line adapter for open-source users
- `ExportUlyssesApp`: shared SwiftUI source used by both direct and App Store app targets

The SwiftPM app is the direct-distribution build. `ExportUlysses.xcodeproj` is the App Store build and defines `APP_STORE`, enables App Sandbox, and archives a single self-contained app. The App Store target never probes Ulysses' group container. Users explicitly select a `.ulbackup` package and destination parent with standard macOS panels.

Security-scoped bookmarks remember the selected backup and destination. The shared exporter receives ordinary paths only and has no knowledge of sandboxing, pricing, App Store Connect, or SwiftUI.

## App Store Configuration

1. Join the Apple Developer Program and create a macOS App ID for `org.deverman.ExportUlysses`.
2. Set the development team on the **Export Ulysses** target in Xcode.
3. Review the included production AppIcon at every required size and replace it only if the product identity changes.
4. Create the app in App Store Connect using the same bundle ID.
5. Configure it as a paid upfront app. No StoreKit or in-app purchase code is required because purchase happens before download and the app has no separately unlocked functionality.
6. Use the Utilities category and macOS 26.0 minimum version.
7. Set the privacy-policy URL to `https://github.com/deverman/export-ulysses/blob/main/PRIVACY.md` after this branch is merged to `main`.
8. Complete App Privacy as **Data Not Collected**. The app has no analytics, accounts, advertising, or network service.

The app includes an in-app privacy settings page and a synthetic sample backup. Reviewers can select **Try Sample Backup**, choose a destination, run preflight, and complete a one-sheet migration without installing Ulysses or using private data.

## Entitlements

`Packaging/AppStore.entitlements` contains only:

- App Sandbox
- user-selected read/write file access
- app-scoped security bookmarks

The direct app uses `Packaging/Direct.entitlements` and keeps automatic local-backup discovery. The CLI is not part of the App Store app bundle.

## Archive And Submit

Open `ExportUlysses.xcodeproj`, select **Any Mac**, then choose **Product > Archive**. Validate and distribute the archive from Xcode Organizer as a Mac App Store build.

The equivalent archive helper is:

```sh
DEVELOPMENT_TEAM=YOURTEAMID swift run -c release release-tool archive-app-store 1.0.0 1
```

The helper opens the resulting archive in Organizer. Signing, validation, and upload remain under Xcode and App Store Connect rather than introducing App Store credentials into this repository.

## Suggested Review Notes

> Export Ulysses is a one-time local migration utility. It reads only a Ulysses `.ulbackup` package selected through NSOpenPanel and writes FSNotes-compatible TextBundles under a destination selected by the reviewer. No account or network service is used. To test without Ulysses, choose Try Sample Backup, select a destination parent, run preflight, and migrate. The app creates one sample TextBundle and validates it before publishing the folder. Ulysses and FSNotes are third-party products; this app is not affiliated with either developer.

## Product And Trademark Notes

The app charges for the convenience of a guided, signed, sandboxed migration workflow. The open-source CLI remains available separately. Store metadata should avoid implying affiliation with Ulysses or FSNotes and should include: “Ulysses and FSNotes are trademarks of their respective owners. Export Ulysses is an independent migration utility.”
