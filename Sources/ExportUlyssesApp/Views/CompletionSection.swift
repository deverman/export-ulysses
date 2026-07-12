import SwiftUI

struct CompletionSection: View {
    let store: MigrationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Finish in FSNotes")
                .font(.headline)
            Text("Already use FSNotes? Keep its current Default Storage and place this migration folder inside it. For a new library, use the migration folder as Default Storage. Review the export report before configuring or moving Trash.")
                .foregroundStyle(.secondary)

            HStack {
                Button("Show Export in Finder", systemImage: "folder") {
                    store.revealExport()
                }
                Button("Open FSNotes", systemImage: "arrow.up.forward.app") {
                    store.openFSNotes()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.green.opacity(0.2))
        }
    }
}
