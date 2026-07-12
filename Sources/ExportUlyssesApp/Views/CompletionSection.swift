import SwiftUI

struct CompletionSection: View {
    let store: MigrationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Finish in FSNotes")
                .font(.headline)
            Text("Set the exported folder as FSNotes Default Storage, then verify that FSNotes Trash points to its Trash subfolder before emptying Trash.")
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
