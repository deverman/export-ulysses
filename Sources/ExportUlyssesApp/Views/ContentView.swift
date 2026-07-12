import SwiftUI

struct ContentView: View {
    let store: MigrationStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    LocationSection(store: store)

                    if store.isWorking {
                        ProgressSection(progress: store.progress)
                    }

                    if !store.checks.isEmpty {
                        PreflightSection(checks: store.checks)
                    }

                    if let summary = store.summary {
                        MigrationSummaryView(summary: summary)
                    }

                    if store.phase == .complete {
                        CompletionSection(store: store)
                    }
                }
                .padding(28)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }

            Divider()
            actionBar
        }
        .navigationTitle("Export Ulysses")
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: headerIcon)
                .font(.system(size: 28))
                .foregroundStyle(headerColor)
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(store.phase.title)
                    .font(.title2.weight(.semibold))
                Text(headerDetail)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    private var actionBar: some View {
        HStack {
            if let error = store.errorMessage, store.phase == .failed {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            if !store.supportJSON.isEmpty {
                Button("Save Support Report") {
                    store.saveSupportReport()
                }
            }
            Spacer()
            if store.phase != .complete {
                Button("Run Preflight") {
                    store.runPreflight()
                }
                .disabled(!store.canCheck)

                Button("Migrate to FSNotes") {
                    store.migrate()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.canMigrate)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
    }

    private var headerIcon: String {
        switch store.phase {
        case .complete: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .checking, .migrating: "arrow.triangle.2.circlepath"
        default: "square.and.arrow.up"
        }
    }

    private var headerColor: Color {
        switch store.phase {
        case .complete: .green
        case .failed: .orange
        default: .accentColor
        }
    }

    private var headerDetail: String {
        switch store.phase {
        case .configuring: "Choose the source backup and a new FSNotes storage folder."
        case .checking: "No notes are being written during preflight."
        case .ready: "Review the checks and migration totals before continuing."
        case .migrating: "The destination is published only after validation passes."
        case .complete: "Your validated FSNotes library is ready."
        case .failed: "Resolve the issue below and run preflight again."
        }
    }
}
