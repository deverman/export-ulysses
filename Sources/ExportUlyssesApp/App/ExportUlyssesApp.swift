import SwiftUI

@main
struct ExportUlyssesApp: App {
    @State private var store = MigrationStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 720, minHeight: 620)
        }
        .defaultSize(width: 820, height: 700)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Choose Ulysses Backup...") {
                    store.chooseBackup()
                }
                .keyboardShortcut("o")

                Button("Choose Destination...") {
                    store.chooseDestination()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }
}
