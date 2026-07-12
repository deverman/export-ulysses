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
                    Text(missingBackupMessage)
                } icon: {
                    Image(systemName: "archivebox.badge.clock")
                }
                .font(.callout)
                .foregroundStyle(.orange)

                if store.supportsAutomaticBackupDiscovery {
                    HStack {
                        Button("Check Again", systemImage: "arrow.clockwise") {
                            store.discoverBackup()
                        }
                        Button("Full Disk Access", systemImage: "lock.open") {
                            store.openFullDiskAccess()
                        }
                    }
                }
                Button("Try Sample Backup", systemImage: "doc.badge.gearshape") {
                    store.useSampleBackup()
                }
            }

            HStack(spacing: 8) {
                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 1)
                Image(systemName: "arrow.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 1)
            }
            .padding(.horizontal, 42)

            LocationRow(
                title: "FSNotes destination",
                icon: "folder",
                path: store.destinationPath,
                placeholder: "Choose a new destination",
                action: store.chooseDestination
            )

            Label("External Folders are not included in Ulysses backups and must be copied separately.", systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var missingBackupMessage: String {
        if store.supportsAutomaticBackupDiscovery {
            "No readable local backup was found. In Ulysses choose Settings > Backup > Backup now, then check again. If a backup already exists, grant this app Full Disk Access."
        } else {
            "Choose a Ulysses .ulbackup package. App Store privacy protections require you to select the backup explicitly."
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
                .font(.title3)
                .foregroundStyle(path.isEmpty ? Color.secondary : Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(path.isEmpty ? placeholder : path)
                    .font(.callout)
                    .foregroundStyle(path.isEmpty ? .orange : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 12)
            Button(action: action) {
                Label(path.isEmpty ? "Choose" : "Change", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .help("Choose \(title.lowercased())")
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }
}
