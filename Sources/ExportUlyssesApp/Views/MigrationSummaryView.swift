import SwiftUI
import UlyssesExporter

struct MigrationSummaryView: View {
    let summary: ExportSummary

    private let columns = [
        GridItem(.adaptive(minimum: 145), spacing: 16)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Migration Preview")
                .font(.headline)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                Metric(label: "Sheets", value: summary.sheets, icon: "doc.text")
                Metric(label: "Images", value: summary.inlineImages, icon: "photo")
                Metric(label: "Attachments", value: summary.fileAttachments, icon: "paperclip")
                Metric(label: "Sheet notes", value: summary.sidebarNotes, icon: "text.bubble")
                Metric(label: "Trash sheets", value: summary.trashSheets, icon: "trash")
                Metric(label: "Missing media", value: summary.missingMedia, icon: "photo.badge.exclamationmark")
            }
        }
    }
}

private struct Metric: View {
    let label: String
    let value: Int
    let icon: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(value.formatted())
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
