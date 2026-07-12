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
                Button("Show Export in Finder") {
                    store.revealExport()
                }
                Button("Open FSNotes") {
                    store.openFSNotes()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
