import Foundation

enum MigrationPhase: Equatable {
    case configuring
    case checking
    case ready
    case migrating
    case complete
    case failed

    var title: String {
        switch self {
        case .configuring: "Choose Migration Locations"
        case .checking: "Checking Your Library"
        case .ready: "Ready to Migrate"
        case .migrating: "Migrating to FSNotes"
        case .complete: "Migration Complete"
        case .failed: "Attention Required"
        }
    }
}

struct MigrationProgress: Equatable {
    var phase = ""
    var completed = 0
    var total = 0

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}
