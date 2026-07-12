import Foundation

public struct AppStoreArchiver {
    private let runner: CommandRunner

    public init(runner: CommandRunner = CommandRunner()) {
        self.runner = runner
    }

    public func archive(
        version: String,
        build: String,
        archiveURL: URL,
        repositoryRoot: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        openOrganizer: Bool
    ) throws {
        try RepositoryRoot.validate(repositoryRoot)
        guard let team = environment["DEVELOPMENT_TEAM"], !team.isEmpty else {
            throw ReleaseConfigurationError.missingEnvironment("DEVELOPMENT_TEAM")
        }
        try FileManager.default.createDirectory(at: archiveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try runner.run([
            "xcodebuild", "-project", repositoryRoot.appendingPathComponent("ExportUlysses.xcodeproj").path,
            "-scheme", "Export Ulysses", "-configuration", "Release",
            "-destination", "generic/platform=macOS", "-archivePath", archiveURL.path,
            "DEVELOPMENT_TEAM=\(team)", "MARKETING_VERSION=\(version)",
            "CURRENT_PROJECT_VERSION=\(build)", "archive"
        ])
        if openOrganizer { try runner.run(["open", archiveURL.path]) }
    }
}
