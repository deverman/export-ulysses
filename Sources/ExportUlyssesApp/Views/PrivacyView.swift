import SwiftUI

struct PrivacyView: View {
    var body: some View {
        Form {
            Section("Privacy") {
                Text("Export Ulysses processes your backup and creates FSNotes files entirely on this Mac.")
                LabeledContent("Data collected", value: "None")
                LabeledContent("Analytics or advertising", value: "None")
                LabeledContent("Automatic uploads", value: "None")
            }

            Section("File Access") {
                Text("The App Store version accesses only locations you select. Security-scoped bookmarks are stored locally to remember those choices.")
            }

            Link("Read the complete privacy policy", destination: URL(string: "https://github.com/deverman/export-ulysses/blob/main/PRIVACY.md")!)
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 520, height: 360)
    }
}
