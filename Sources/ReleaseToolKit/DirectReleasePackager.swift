import CryptoKit
import Foundation

public struct DirectReleasePackager {
    private let fileManager: FileManager
    private let runner: CommandRunner

    public init(fileManager: FileManager = .default, runner: CommandRunner = CommandRunner()) {
        self.fileManager = fileManager
        self.runner = runner
    }

    public func package(
        configuration: DirectReleaseConfiguration,
        repositoryRoot: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        try RepositoryRoot.validate(repositoryRoot, fileManager: fileManager)
        let previousDirectory = fileManager.currentDirectoryPath
        guard fileManager.changeCurrentDirectoryPath(repositoryRoot.path) else {
            throw CocoaError(.fileReadNoPermission)
        }
        defer { _ = fileManager.changeCurrentDirectoryPath(previousDirectory) }

        let notarization = try NotarizationCredentials.resolve(environment: environment)
        let signingIdentity = environment["CODESIGN_IDENTITY"].flatMap { $0.isEmpty ? nil : $0 }
        if notarization != nil, signingIdentity == nil {
            throw ReleaseConfigurationError.missingEnvironment("CODESIGN_IDENTITY")
        }

        let arch = configuration.architecture
        try runner.run(["swift", "build", "-c", "release", "--arch", arch])

        let build = repositoryRoot.appendingPathComponent(".build/\(arch)-apple-macosx/release")
        let cli = build.appendingPathComponent("export-ulysses")
        let appBinary = build.appendingPathComponent("ExportUlyssesApp")
        try requireExecutable(cli)
        try requireExecutable(appBinary)

        let actualVersion = try runner.run([cli.path, "--version"], captureOutput: true)
        guard actualVersion == configuration.version else {
            throw ReleaseConfigurationError.versionMismatch(expected: configuration.version, actual: actualVersion)
        }

        let dist = repositoryRoot.appendingPathComponent("dist", isDirectory: true)
        let package = dist.appendingPathComponent(configuration.artifactName, isDirectory: true)
        let zip = dist.appendingPathComponent("\(configuration.artifactName).zip")
        try fileManager.createDirectory(at: dist, withIntermediateDirectories: true)
        try removeIfPresent(package)
        try removeIfPresent(zip)
        try fileManager.createDirectory(at: package, withIntermediateDirectories: true)

        try fileManager.copyItem(at: cli, to: package.appendingPathComponent("export-ulysses"))
        for name in ["README.md", "LICENSE"] {
            try fileManager.copyItem(at: repositoryRoot.appendingPathComponent(name), to: package.appendingPathComponent(name))
        }
        try createAppBundle(appBinary: appBinary, package: package, version: configuration.version, repositoryRoot: repositoryRoot)
        try runner.run(["xattr", "-cr", package.path])

        if let identity = signingIdentity {
            try sign(package: package, identity: identity, repositoryRoot: repositoryRoot)
        }

        try runner.run(["ditto", "-c", "-k", "--keepParent", package.path, zip.path])
        if let credentials = notarization {
            try runner.run([
                "xcrun", "notarytool", "submit", zip.path,
                "--apple-id", credentials.appleID,
                "--team-id", credentials.teamID,
                "--password", credentials.appPassword,
                "--wait"
            ])
            try runner.run(["xcrun", "stapler", "staple", package.appendingPathComponent("Export Ulysses.app").path])
            try fileManager.removeItem(at: zip)
            try runner.run(["ditto", "-c", "-k", "--keepParent", package.path, zip.path])
        }
        try writeChecksum(for: zip)
        try fileManager.removeItem(at: package)
        return zip
    }

    private func createAppBundle(appBinary: URL, package: URL, version: String, repositoryRoot: URL) throws {
        let app = package.appendingPathComponent("Export Ulysses.app", isDirectory: true)
        let macOS = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try fileManager.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fileManager.copyItem(at: appBinary, to: macOS.appendingPathComponent("Export Ulysses"))

        let sourcePlist = repositoryRoot.appendingPathComponent("Packaging/ExportUlyssesApp-Info.plist")
        let data = try Data(contentsOf: sourcePlist)
        guard var plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        plist["CFBundleShortVersionString"] = version
        let output = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try output.write(to: app.appendingPathComponent("Contents/Info.plist"), options: .atomic)
    }

    private func sign(package: URL, identity: String, repositoryRoot: URL) throws {
        let cli = package.appendingPathComponent("export-ulysses").path
        let app = package.appendingPathComponent("Export Ulysses.app").path
        try runner.run(["codesign", "--force", "--options", "runtime", "--timestamp", "--sign", identity, cli])
        try runner.run(["codesign", "--verify", "--strict", "--verbose=2", cli])
        try runner.run([
            "codesign", "--force", "--options", "runtime", "--timestamp", "--sign", identity,
            "--entitlements", repositoryRoot.appendingPathComponent("Packaging/Direct.entitlements").path, app
        ])
        try runner.run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", app])
    }

    private func requireExecutable(_ url: URL) throws {
        guard fileManager.isExecutableFile(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
        }
    }

    private func removeIfPresent(_ url: URL) throws {
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }

    private func writeChecksum(for url: URL) throws {
        let digest = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        let line = "\(digest)  \(url.lastPathComponent)\n"
        try line.write(to: URL(fileURLWithPath: url.path + ".sha256"), atomically: true, encoding: .utf8)
    }
}
