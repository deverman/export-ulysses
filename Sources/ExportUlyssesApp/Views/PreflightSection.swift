import SwiftUI
import UlyssesExporter

struct PreflightSection: View {
    let checks: [PreflightCheck]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preflight")
                .font(.headline)

            ForEach(Array(checks.enumerated()), id: \.offset) { _, check in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon(for: check.status))
                        .foregroundStyle(color(for: check.status))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(check.name)
                            .font(.subheadline.weight(.medium))
                        Text(check.message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func icon(for status: PreflightCheck.Status) -> String {
        switch status {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failure: "xmark.circle.fill"
        }
    }

    private func color(for status: PreflightCheck.Status) -> Color {
        switch status {
        case .success: .green
        case .warning: .orange
        case .failure: .red
        }
    }
}

struct ProgressSection: View {
    let progress: MigrationProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(progress.phase)
                    .font(.headline)
                Spacer()
                if progress.total > 0 {
                    Text("\(progress.completed) of \(progress.total)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: progress.fraction)
                .progressViewStyle(.linear)
        }
        .padding(16)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }
}
