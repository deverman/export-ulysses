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

                    if let error = store.errorMessage, store.phase == .failed {
                        ErrorBanner(message: error)
                    }

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
            PhaseBadge(phase: store.phase)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    private var actionBar: some View {
        HStack {
            if !store.supportJSON.isEmpty {
                Button("Save Support Report", systemImage: "square.and.arrow.down") {
                    store.saveSupportReport()
                }
            }
            Spacer()
            if store.phase != .complete {
                Button("Check Migration", systemImage: "checklist") {
                    store.runPreflight()
                }
                .disabled(!store.canCheck)

                Button("Migrate to FSNotes", systemImage: "arrow.right.circle.fill") {
                    store.migrate()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.canMigrate)
                .keyboardShortcut(.defaultAction)
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

private struct PhaseBadge: View {
    let phase: MigrationPhase

    var body: some View {
        Label(label, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var label: String {
        switch phase {
        case .configuring: "Setup"
        case .checking: "Checking"
        case .ready: "Ready"
        case .migrating: "Migrating"
        case .complete: "Complete"
        case .failed: "Needs Attention"
        }
    }

    private var icon: String {
        switch phase {
        case .configuring: "1.circle.fill"
        case .checking, .migrating: "arrow.triangle.2.circlepath"
        case .ready: "checkmark.circle.fill"
        case .complete: "checkmark.seal.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch phase {
        case .ready, .complete: .green
        case .failed: .orange
        default: .accentColor
        }
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Migration check needs attention")
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.orange.opacity(0.25))
        }
    }
}
