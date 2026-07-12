import ArgumentParser
import Foundation
import ReleaseToolKit

@main
struct ReleaseTool: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "release-tool",
        abstract: "Build and package export-ulysses releases.",
        subcommands: [Package.self, ArchiveAppStore.self]
    )
}

extension ReleaseTool {
    struct Package: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Build, sign, notarize, and checksum a direct release.")

        @Argument(help: "Release version without a v prefix.")
        var version: String

        @Argument(help: "Target architecture: arm64 or x86_64.")
        var architecture: String

        func run() throws {
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            let config = try DirectReleaseConfiguration(version: version, architecture: architecture)
            let artifact = try DirectReleasePackager().package(configuration: config, repositoryRoot: root)
            print("Created \(artifact.path)")
        }
    }

    struct ArchiveAppStore: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a signed App Store archive with Xcode.")

        @Argument(help: "Marketing version without a v prefix.")
        var version: String = "1.0.0"

        @Argument(help: "App Store build number.")
        var build: String = "1"

        @Option(help: "Archive output path.")
        var archivePath: String?

        @Flag(inversion: .prefixedNo, help: "Open the completed archive in Xcode Organizer.")
        var open = true

        func run() throws {
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            let output = archivePath.map { URL(fileURLWithPath: $0) }
                ?? root.appendingPathComponent("dist/Export Ulysses-\(version).xcarchive")
            try AppStoreArchiver().archive(
                version: version,
                build: build,
                archiveURL: output,
                repositoryRoot: root,
                openOrganizer: open
            )
            print("Created \(output.path)")
        }
    }
}
