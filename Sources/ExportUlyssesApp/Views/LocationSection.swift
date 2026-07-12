import SwiftUI

struct LocationSection: View {
    let store: MigrationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Migration Locations")
                .font(.headline)

            LocationRow(
                title: "Ulysses backup",
                icon: "archivebox",
                path: store.backupPath,
                placeholder: "No local backup found",
                action: store.chooseBackup
            )

            if store.backupPath.isEmpty {
                Label {
                    Text("No readable local backup was found. In Ulysses choose **Settings > Backup > Backup now**, then check again. If a backup already exists, grant this app Full Disk Access.")
                } icon: {
                    Image(systemName: "archivebox.badge.clock")
                }
                .font(.callout)
                .foregroundStyle(.orange)

                HStack {
                    Button("Check Again", systemImage: "arrow.clockwise") {
                        store.discoverBackup()
                    }
                    Button("Full Disk Access", systemImage: "lock.open") {
                        store.openFullDiskAccess()
                    }
                }
            }

            LocationRow(
                title: "FSNotes destination",
                icon: "folder",
                path: store.destinationPath,
                placeholder: "Choose a new destination",
                action: store.chooseDestination
            )

            Label("External Folders are not included in Ulysses backups and must be copied separately.", systemImage: "exclamationmark.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LocationRow: View {
    let title: String
    let icon: String
    let path: String
    let placeholder: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(path.isEmpty ? placeholder : path)
                    .font(.callout)
                    .foregroundStyle(path.isEmpty ? .orange : .secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 12)
            Button(action: action) {
                Image(systemName: "folder.badge.plus")
            }
            .help("Choose \(title.lowercased())")
        }
        .padding(.vertical, 4)
    }
}
